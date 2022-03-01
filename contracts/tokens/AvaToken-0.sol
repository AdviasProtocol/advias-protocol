//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IPool} from '../interfaces/IPool.sol';
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {WadRayMath} from '../libraries/WadRayMath.sol';
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPoolAddressesProvider} from '../interfaces/IPoolAddressesProvider.sol';
import {IRouter} from '../interfaces/IRouter.sol';
import {IExchangeRateData} from '../interfaces/IExchangeRateData.sol';

import {IAvaToken} from '../interfaces/IAvaToken.sol';
import {IPoolAssetData} from '../interfaces/IPoolAssetData.sol';
import {IRewardsBase} from './IRewardsBase.sol';
import {RewardsTokenBase} from './RewardsTokenBase.sol';

import "hardhat/console.sol";


// represents wUST deposited
// all underlying gets sent to anchor
// asset held in this contract is the yield asset like aUST
contract AvaToken0 is RewardsTokenBase, IAvaToken {
  using SafeMath for uint256;
  using WadRayMath for uint256;
  using SafeERC20 for IERC20;

  uint8 immutable private _decimals;

  IPoolAddressesProvider public ADDRESSES_PROVIDER;
  IPoolAssetData private _poolAssetData;
  IPool private _pool;

  uint256 private _dividendSupply;
  address private _dividendsAddress; // protocol token
  uint256 private dividendFactor;

  address private savingsTokenFactory;

  IERC20 private _routerWrapped;
  uint8 private _routerAssetDecimals;

  IERC20 private _routerUnderlying;

  /* address private reserve; */

  address internal _underlyingAsset; // wUST

  uint256 private _routerTotalScaledSupply;
  uint256 private _routerSuppliedTotalScaledSupply; // amount trackd at a discount

  IRewardsBase internal _rewardsBase;

  /*
  * - 0 = sharedTreasury
  * - 1 = sharedTreasury
  * - 2 = reserves
  */

  constructor(
      address provider,
      address underlyingAsset,
      uint8 decimals
  ) RewardsTokenBase("", "") {
      string memory underlyingAssetName = IERC20Metadata(underlyingAsset).name();
      string memory underlyingAssetSymbol = IERC20Metadata(underlyingAsset).symbol();

      string memory name = string(abi.encodePacked("Advias ", underlyingAssetName));
      string memory symbol = string(abi.encodePacked("avas", underlyingAssetSymbol, "s"));

      _decimals = decimals;
      _setDecimals(decimals);
      _setName(name);
      _setSymbol(symbol);

      ADDRESSES_PROVIDER = IPoolAddressesProvider(provider);
      _pool = IPool(ADDRESSES_PROVIDER.getPool());
      _poolAssetData = IPoolAssetData(ADDRESSES_PROVIDER.getPoolAssetData());
      savingsTokenFactory = ADDRESSES_PROVIDER.getSavingsTokenFactory();
      _underlyingAsset = underlyingAsset;
  }

  function decimals() public view virtual override returns (uint8) {
      return _decimals;
  }

  modifier onlyRewardsTokenFactory() {
    require(msg.sender == address(ADDRESSES_PROVIDER.getRewardsTokenFactory()), "Error: Only rewards factory can be sender.");
    _;
  }

  function setRewards(address _rewards) external override onlyRewardsTokenFactory {
      _rewardsBase = IRewardsBase(_rewards);
  }

  // where to send dividend factor to
  function setDividends(address to, uint256 factor) external override onlyPoolAdmin {
      require(factor <= 1e18, "Error: Factor greater than max");
      _dividendsAddress = to;
      dividendFactor = factor;
      _addRewardsBlacklist(to);
  }

  function _addRewardsBlacklist(address user) public onlyPoolAdmin {
      addRewardsBlacklist(user);
  }

  function _removeRewardsBlacklist(address user) public onlyPoolAdmin {
      removeRewardsBlacklist(user);
  }


  modifier onlyPool() {
    require(msg.sender == address(_pool), "Error: Only pool can be sender.");
    _;
  }

  modifier onlySavingsTokenFactory() {
    require(msg.sender == savingsTokenFactory, "Error: Only fatory can be sender.");
    _;
  }

  // amount = depositAmount - routerAmount
  /**
   * @dev Mints avaToken to user and supplies to Anchor or vault
   * supply() then reupdates totalDepositsLendable on the more accurate return value of AUST
   **/
  function mint_(address account, uint256 amount, uint256 supplyAmount, uint256 exchangeRate) external override onlyPool {
      _pool.updateTotalDepositsLendable(_underlyingAsset, amount.add(supplyAmount), 0);
      uint256 currentTimestamp = block.timestamp;
      // supply to router
      uint256 amountFromShared;
      // reserves to cover fees
      if (supplyAmount != 0) {
          uint256 amountBack = supply(supplyAmount);
          // total balance for treasury of shared assets to cover fees
          uint256 totalSharedSupplyAvailable = super.balanceOf(address(this), 0).wadMul(exchangeRate);
          uint256 amountToBurn;

          if (amountBack < supplyAmount && totalSharedSupplyAvailable != 0) {
              // difference from supplied to amount back
              uint256 amountToBackDelta = supplyAmount.sub(amountBack); // amount needed to fill spread from amount routerd >> routerd back value

              if (totalSharedSupplyAvailable >= amountToBackDelta) {
                  // `if` we have enough to cover
                  amountToBurn = amountToBackDelta;
              } else {
                  // use what is available
                  amountToBurn = totalSharedSupplyAvailable;
              }
              _burn(
                  address(this),
                  0,
                  amountToBurn.wadDiv(exchangeRate)
              );
          }
          amountFromShared = amountBack.add(amountToBurn);
      }

      uint256 scaledAmount = amount.add(amountFromShared).wadDiv(exchangeRate);
      _mint(account, scaledAmount);
      emit Mint(account, amount, exchangeRate);
  }

  //the interest rate and exchange is is not dependent on totalSupply or totalScaledSupply so we are aable to
  // mint outside of that
  // sharedTreasury is used for covering user fees
  /**
   * @dev Controlld by the reserve factor of the poolAsset, mints to treasury fund and or dividend fund
   * Shared treasury is used for covering user fees from anchor router
   **/
  function mintToSharedTreasury(uint256 amount, uint256 exchangeRate) external override onlyPool {
      if (amount == 0) {
        return;
      }

      uint256 scaledAmount = amount.wadDiv(exchangeRate);

      uint256 dividendAmount;
      if (
          _dividendsAddress != address(0) ||
          dividendFactor != 0
      ) {
          dividendAmount = scaledAmount.wadMul(dividendFactor);
          // do not include in rewards
          // mint to the protools token
          _mint(_dividendsAddress, dividendAmount);
          // increase manually to keep track of for indexing
          _dividendSupply += dividendAmount;
      }

      // 1155ERC-AVA
      _mint(
          address(this),
          0,
          scaledAmount.sub(dividendAmount)
      );
      emit Mint(address(this), amount, exchangeRate);
  }

  /**
   * @dev Supplies excess appreciation of AUST to liquidity standard vault
   **/
  function supplyLiquidityVault(address asset, address vault, uint256 bufferFactor) external override onlyPool {
      ( , uint256 routerExchangeRate) = IExchangeRateData(_poolAssetData.getExchangeRateData(_underlyingAsset)).getInterestData();
      uint256 balance = _routerWrapped.balanceOf(address(this)).wadMul(routerExchangeRate);

      uint256 totalSupply = totalSupply();
      uint256 bufferBalance = balance.add(balance.wadMul(bufferFactor));

      if (totalSupply > balance) {
          uint256 valueDelta = totalSupply.sub(balance);
          uint256 amountDelta = valueDelta.wadDiv(routerExchangeRate);
          // router require 10 eth

          if (amountDelta <= 10e18) { return; }

          IRouter(_poolAssetData.getRouter(_underlyingAsset)).redeemNR(
              amountDelta,
              vault,
              asset
          );
      }
  }

  /**
   * @dev Manually tracks mints to the dividend address
   * Used by protocol token
   **/
  function dividendSupply() external view override returns (uint256) {
      return _dividendSupply;
  }

  /**
   * @dev Supplies underlying asset to Anchor or vault for AUST in return
   **/
  function supply(uint256 amount) public override onlyPool returns (uint256) {

      //amountBack is underlyying asset we are supplying
      //this may not be the underlying asset of this avastoken
      //decimals can be different
      // applied in _routerSuppliedTotalScaledSupply below
      // amountBack is either actual local amount, or
      // routerd estimated amount
      ( , uint256 amountBack) = IRouter(_poolAssetData.getRouter(_underlyingAsset)).deposit(
          _underlyingAsset,
          amount,
          0,
          address(this)
      );

      ( , uint256 exchangeRate) = IExchangeRateData(_poolAssetData.getExchangeRateData(_underlyingAsset)).getInterestData();

      _routerTotalScaledSupply = _routerTotalScaledSupply.add(amountBack.wadDiv(exchangeRate)); // estimates aUST back | mimics balanceOf - this is needed due to bridging done separately from tx

      uint256 depositsSuppliedExchangeRate = _poolAssetData.getDepositsSuppliedExchangeRate(_underlyingAsset);
      _routerSuppliedTotalScaledSupply = _routerSuppliedTotalScaledSupply.add(amountBack.mul(10**_decimals).div(10**_routerAssetDecimals).wadDiv(depositsSuppliedExchangeRate));
      console.log("_routerSuppliedTotalScaledSupply", _routerSuppliedTotalScaledSupply);
      // deposits lendable referenced in avaToken underlying asset
      _pool.updateTotalDepositsLendable(_underlyingAsset, 0, amount);

      return amountBack.mul(10**_decimals).div(10**_routerAssetDecimals);

      emit RouterDeposit(
          amountBack
      );

  }

  /**
   * @dev Redeem underlying asset from Anchor or vault
   **/
  function redeem(uint256 amount, address to, bool emergency) public override onlyPool returns (bool) {
      ( , uint256 exchangeRate) = IExchangeRateData(_poolAssetData.getExchangeRateData(_underlyingAsset)).getInterestData();

      // update to router decimals.  even if swapping to another asset we use ust
      uint256 scaledAmount = (amount.mul(10**_routerAssetDecimals).div(10**_decimals)).wadDiv(exchangeRate);
      /* uint256 scaledAmount = amount.wadDiv(exchangeRate); */

      uint256 balanceAvailable = _routerWrapped.balanceOf(address(this));

      if (!emergency) {
          // if user is withddrawing and requires routerd asset, make sure we can accomodate
          require(balanceAvailable > scaledAmount, "Error: Not enough balance to redeem from router.");
      } else {
          if (balanceAvailable < scaledAmount) {
              scaledAmount = balanceAvailable;
              amount = scaledAmount.wadMul(exchangeRate); // get value of underlying
          }
      }
      /* uint256 amountReturned = IRouter(router).redeem(
          scaledAmount,
          to
      ); */
      uint256 amountReturned = IRouter(_poolAssetData.getRouter(_underlyingAsset)).redeem(
          scaledAmount,
          address(this),
          _underlyingAsset
      );

      // amountReturned referenced in avaToken underlying asset
      if (!emergency) {
          require(amountReturned > 0, "Error: Router amount return is zero.");
      }


      // manually tracking aUST total balanced to router
      // this is tracking the actual amount and not the allotted amount for depositors
      _routerTotalScaledSupply = _routerTotalScaledSupply.sub(scaledAmount);


      // track the allotted amount for depositors from router
      // this is discounted due to possible miscalculation errors betweeen bridging
      uint256 depositsSuppliedExchangeRate = _poolAssetData.getDepositsSuppliedExchangeRate(_underlyingAsset);
      /* _routerSuppliedTotalScaledSupply = _routerSuppliedTotalScaledSupply.sub(amountReturned.mul(10**_decimals).div(10**_routerAssetDecimals).wadDiv(depositsSuppliedExchangeRate)); */
      _routerSuppliedTotalScaledSupply = _routerSuppliedTotalScaledSupply.sub(amountReturned.wadDiv(depositsSuppliedExchangeRate));

      // update lendable if rebalance into contract
      if (to == address(this)) {
          _pool.updateTotalDepositsLendable(_underlyingAsset, amountReturned, 0);
          /* _pool.updateTotalDepositsLendable(_underlyingAsset, amountReturned.mul(10**_decimals).div(10**_routerAssetDecimals), 0); */
      }

      emit RouterRedeem(
          to,
          amount
      );

      return true;
  }


  /**
   * @dev Sets router address to use
   **/
  function initRouter() public override {
      address router = _poolAssetData.getRouter(_underlyingAsset);
      require(router != address(0), "Error: Router is zero address");
      uint256 MAX = ~uint256(0);
      _routerWrapped = IERC20(IRouter(router)._wrappedAsset());
      _routerUnderlying = IERC20(IRouter(router)._underlyingAsset());
      _routerWrapped.approve(router, MAX);
      IERC20(_underlyingAsset).approve(router, MAX);
      _routerAssetDecimals = IERC20Metadata(address(_routerUnderlying)).decimals();
  }

  /**
   * @dev total supply of avaToken as scaled
   **/
  function totalScaledSupply() external view override returns (uint256) {
      return super.totalSupply();
  }

  /**
   * @dev total supply of avaToken as scaled*exchangeRate
   * exchangeRate is simulated by using latest interest rate and last updated timestamp to now delta
   **/
  function totalSupply() public view override returns (uint256) {
      uint256 simulateOverallExchangeRate = _poolAssetData.simulateOverallExchangeRate(_underlyingAsset);
      return super.totalSupply().wadMul(simulateOverallExchangeRate);
  }

  /**
   * @dev Balance of user avaToken as scaled
   * @param account Address of user
   **/
  function balanceOfScaled(address account) public view override returns (uint256) {
      return super.balanceOf(account);
  }

  /**
   * @dev Balance of user avaToken as scaled*exchangeRate
   * @param account Address of user
   * exchangeRate is simulated by using latest interest rate and last updated timestamp to now delta
   **/
  function balanceOf(address account) public view override returns (uint256) {
      uint256 simulateOverallExchangeRate = _poolAssetData.simulateOverallExchangeRate(_underlyingAsset);
      console.log("in ava balanceOf simulateOverallExchangeRate", simulateOverallExchangeRate);

      return super.balanceOf(account).wadMul(simulateOverallExchangeRate);
  }

  /* function routerTotalScaledSupply() public view override returns (uint256) {
      return _routerTotalScaledSupply; // balance of aust
  }

  // total supply of UST available in anchor
  // this is the absolute total we assume is there
  function routerTotalSupply() public view override returns (uint256) {
      ( , uint256 exchangeRate) = IExchangeRateData(_poolAssetData.getExchangeRateData(_underlyingAsset)).getInterestData();
      return _routerTotalScaledSupply.wadMul(exchangeRate);
  } */

  /**
   * @dev Total amount of underlying asset at scale that has been deposited to Anchor
   **/
  function routerSuppliedTotalScaledSupply() public view override returns (uint256) {
      return _routerSuppliedTotalScaledSupply;
  }

  /**
   * @dev Total amount of underlying asset that has been deposited to Anchor
   **/
  function routerSuppliedTotalSupply() public view override returns (uint256) {
      uint256 depositsSuppliedExchangeRate = _poolAssetData.simulateDepositsSuppliedExchangeRate(_underlyingAsset);
      return _routerSuppliedTotalScaledSupply.wadMul(depositsSuppliedExchangeRate);
  }

  /**
   * @dev Balance of routed wrapped/yield asset
   * used to ensure withdraws aren't over reaching on possible bridge delays
   **/
  function routerSuppliedScaledBalance() external view override returns (uint256) {
      uint256 routerScaledBalance = _routerWrapped.balanceOf(address(this));
      return routerScaledBalance;
  }

  modifier onlyPoolAdmin() {
    require(msg.sender == address(ADDRESSES_PROVIDER.getPoolAdmin()), "Error: Only admin can be caller.");
    _;
  }

  // total amount loaned out
  // used to get savings rate
  /**
   * @dev Total supply of underlying assets that are designated to lending
   * This is a manually tracked version of balanceOf due to bridging lag
   **/
  function lendableTotalSupply() public view override returns (uint256) {
      return _poolAssetData.simulateLendableTotalSupply(_underlyingAsset);
  }

  function lendableTotalSupplyPrincipal() public view override returns (uint256) {
      return _poolAssetData.getTotalDepositsLendable(_underlyingAsset);
  }

  function transferUnderlyingTo(address account, uint256 amount) external override onlyPool returns (uint256) {
      IERC20(_underlyingAsset).safeTransfer(account, amount);
      return amount;
  }

  /**
   * @dev Burns avaToken and redeems AUST to UST
   * @param account Address to burn from and have vault or anchor sent UST to
   * @param amount Amount to burn
   * @param redeemedAmount Address to send AUST to
   * @param exchangeRate AvaToken exchange rate
   * amount minus redeemAmount is the amount of underlying asset of avaToken that pool sends to account
   **/
  function burn(address account, uint256 amount, uint256 redeemedAmount, uint256 exchangeRate) external override onlyPool {

      uint256 amountScaled = amount.wadDiv(exchangeRate);
      require(amountScaled != 0, "Error: Invalid burn amount");
      _burn(account, amountScaled);
      IERC20(_underlyingAsset).safeTransfer(account, amount.sub(redeemedAmount));

      _pool.updateTotalDepositsLendable(_underlyingAsset, 0, amount.sub(redeemedAmount));

      emit Burn(account, amount, exchangeRate);
  }

  /**
   * @dev Burns avaToken and sends AUST - router wrapped - to `to` address
   * @param account Address to burn from
   * @param amount Amount to burn represented in underlying asset like UST
   * @param _to Address to send AUST to
   * @param exchangeRate AvaToken exchange rate
   * Note: The underlying asset doesn't become available since savings is minted so we don't update w/ updateTotalDepositsLendable
   **/
  function burnTo(address account, uint256 amount, address _to, uint256 exchangeRate) external override onlyPool {
      uint256 amountScaled = amount.wadDiv(exchangeRate);
      require(amountScaled != 0, "Error: Invalid burn amount");
      _burn(account, amountScaled);


      ( , uint256 routerExchangeRate) = IExchangeRateData(_poolAssetData.getExchangeRateData(_underlyingAsset)).getInterestData();
      uint256 toAmount = amount.wadDiv(routerExchangeRate);
      // send the `underlying` asset in contract which is the wrapped asset of the represending underlying
      _routerWrapped.safeTransfer(_to, toAmount);

      emit Burn(account, amount, exchangeRate);
  }

  /**
   * @dev For internal usage in the logic of the parent contract IncentivizedERC20
   **/
  function _getRewardsInstance() internal view override returns (IRewardsBase) {
      return _rewardsBase;
  }

  /**
   * @dev Returns the address of the incentives controller contract
   **/
  function getRewardsInstance() external view override returns (IRewardsBase) {
      return _getRewardsInstance();
  }

  function getRouterUnderlying() external view override returns (address) {
      return address(_routerUnderlying);
  }

}
