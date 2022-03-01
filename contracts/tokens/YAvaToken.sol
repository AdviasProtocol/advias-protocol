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

/**
 * @title YAvaToken
 * @author Advias
 * @title avasToken for underlying assets that are yield assets that require exchange rates to receive the balances
 * The main use is for collateral assets to be burned and minted as savings assets due to protocol logic
 */
contract YAvaToken is RewardsTokenBase, IAvaToken {
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
      /* initRouter(); */
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

  // modifier onlySavingsTokenFactory() {
  //   require(msg.sender == savingsTokenFactory, "Error: Only fatory can be sender.");
  //   _;
  // }

  // amount = depositAmount - routerAmount
  /**
   * @dev Mints avaToken to user and supplies to Anchor or vault
   * supply() then reupdates totalDepositsLendable on the more accurate return value of AUST
   **/
  function mint_(address account, uint256 amount, uint256 supplyAmount, uint256 exchangeRate) external override onlyPool {
      // in case of updating asset to be borrowed, we will track the lendable supply
      _pool.updateTotalDepositsLendable(_underlyingAsset, amount.add(supplyAmount), 0);
      _mint(account, amount);
      emit Mint(account, amount, exchangeRate);
  }

  /**
   * @dev Controlld by the reserve factor of the poolAsset, mints to treasury fund and or dividend fund
   * Shared treasury is used for covering user fees from anchor router
   **/
  function mintToSharedTreasury(uint256 amount, uint256 exchangeRate) external override onlyPool {}

  /**
   * @dev Supplies excess appreciation of AUST to liquidity standard vault
   **/
  function supplyLiquidityVault(address asset, address vault, uint256 bufferFactor) external override onlyPool {
      return;
  }

  /**
   * @dev Manually tracks mints to the dividend address
   * Used by protocol token
   **/
  function dividendSupply() external view override returns (uint256) {
      return 0;
  }

  /**
   * @dev Supplies underlying asset to Anchor or vault for AUST in return
   **/
  function supply(uint256 amount) public override onlyPool returns (uint256) {
      return 0;
  }

  /**
   * @dev Redeem underlying asset from Anchor or vault
   **/
  function redeem(uint256 amount, address to, bool emergency) public override onlyPool returns (bool) {
      return true;
  }


  /**
   * @dev Sets router address to use
   **/
  function initRouter() public override {
      return;
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
      return super.totalSupply();
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
      return super.balanceOf(account);
  }

  /* function routerTotalScaledSupply() public view override returns (uint256) {
      return _routerTotalScaledSupply; // balance of aust
  }

  /**
   * @dev Total amount of underlying asset at scale that has been deposited to Anchor
   **/
  function routerSuppliedTotalScaledSupply() public view override returns (uint256) {
      return 0;
  }

  /**
   * @dev Total amount of underlying asset that has been deposited to Anchor
   **/
  function routerSuppliedTotalSupply() public view override returns (uint256) {
      return 0;
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
   * @dev Burns avaToken and sends AUST to `to` address
   * @param account Address to burn from
   * @param amount Amount to burn
   * @param _to Address to send AUST to
   * @param exchangeRate AvaToken exchange rate
   **/
  function burnTo(address account, uint256 amount, address _to, uint256 exchangeRate) external override onlyPool {
      uint256 amountScaled = amount.wadDiv(exchangeRate);
      require(amountScaled != 0, "Error: Invalid burn amount");
      _burn(account, amountScaled);


      ( , uint256 routerExchangeRate) = IExchangeRateData(_poolAssetData.getExchangeRateData(_underlyingAsset)).getInterestData();
      uint256 toCollateralAmount = amount.wadDiv(routerExchangeRate);
      _routerWrapped.safeTransfer(_to, toCollateralAmount);

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
