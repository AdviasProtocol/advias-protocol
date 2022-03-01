//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IPool} from '../interfaces/IPool.sol';

import {WadRayMath} from '../libraries/WadRayMath.sol';
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPoolAddressesProvider} from '../interfaces/IPoolAddressesProvider.sol';
import {ICollateralToken} from '../interfaces/ICollateralToken.sol';
import {IRouter} from '../interfaces/IRouter.sol';
import {IExchangeRateData} from '../interfaces/IExchangeRateData.sol';

import {IPoolAssetData} from '../interfaces/IPoolAssetData.sol';

import "hardhat/console.sol";


// represents wUST deposited
// all underlying gets sent to anchor
contract CollateralToken is ERC20, ICollateralToken {
  using SafeMath for uint256;
  using WadRayMath for uint256;
  using SafeERC20 for IERC20;

  uint8 immutable private _decimals;

  IPoolAddressesProvider public ADDRESSES_PROVIDER;
  IPoolAssetData private _poolAssetData;
  IPool private _pool;

  /* IRouter private _router; */

  // address private collateralTokenFactory;

  address private reserve;
  address private vault;

  address internal _underlyingAsset;

  IERC20 private _routerWrapped;
  uint8 private _routerAssetDecimals;

  IERC20 private _routerUnderlying;

  mapping(address => uint256) private _initialExchangeRates;

  // scaled value used for principal as _collateralPrincipalScaled * _initialExchangeRates
  // used in LTV formula as debt/_collateralPrincipalScaled
  // used as a base for bonusFactor redebt as (currentCollateralValue - (_collateralPrincipalScaled * _initialExchangeRates)) * bonus_%
  /* mapping(address => uint256) private _collateralPrincipalScaled; */

  /* mapping(address => uint256) private _principalBalance; */

  /* mapping(address => address) private _accountCollateralInstances; */

  uint256 private routerTotalSupply; // manually tracked due  to router delays
  string private _name;
  string private _symbol;

  constructor(
      address provider,
      address underlyingAsset,
      uint8 decimals
  ) ERC20("", "") {
      string memory underlyingAssetName = ERC20(underlyingAsset).name();
      string memory underlyingAssetSymbol = ERC20(underlyingAsset).symbol();

      string memory name = string(abi.encodePacked("Advias Collateral Token ", underlyingAssetName));
      string memory symbol = string(abi.encodePacked("avas", underlyingAssetSymbol, "s"));

      _decimals = decimals;

      ADDRESSES_PROVIDER = IPoolAddressesProvider(provider);
      _pool = IPool(ADDRESSES_PROVIDER.getPool());
      _poolAssetData = IPoolAssetData(ADDRESSES_PROVIDER.getPoolAssetData());
      // collateralTokenFactory = ADDRESSES_PROVIDER.getCollateralTokenFactory();
      _underlyingAsset = underlyingAsset;
      _name = name;
      _symbol = symbol;
      reserve = msg.sender;
      vault = msg.sender;
      /* initRouter(); */
  }

  function decimals() public view virtual override returns (uint8) {
      return _decimals;
  }

  function name() public view virtual override returns (string memory) {
      return _name;
  }

  function symbol() public view virtual override returns (string memory) {
      return _symbol;
  }

  /**
   * @dev Sets Router address to integrate with for sending AUST to and redeeming UST
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

  modifier onlyPool() {
    require(msg.sender == address(_pool), "Error: Only pool can be sender.");
    _;
  }

  modifier onlyPoolOrLiquidationCaller() {
    require(msg.sender == address(_pool) || msg.sender == ADDRESSES_PROVIDER.getLiquidationCaller(), "Error: Only pool can be sender.");
    _;
  }

  // modifier onlyCollateralTokenFactory() {
  //   require(msg.sender == collateralTokenFactory, "Error: Only factory can be sender.");
  //   _;
  // }

  /**
   * @dev Mints avasTokenC as `amount` / `exchangeRate` and supplies `amount` to Anchor
   **/
  function mint(address account, uint256 amount, uint256 exchangeRate, bool supply_) external override onlyPool returns (uint256, uint256) {

      uint256 amountBack = amount;
      if (supply_) {
          amountBack = supply(
              amount
          );
      }

      uint256 scaledAmount = amountBack.wadDiv(exchangeRate);

      _initialExchangeRates[account] = exchangeRate;

      _mint(account, scaledAmount);

      emit Mint(account, amount, exchangeRate);

      return (amountBack, scaledAmount);
  }

  /**
   * @dev Mints factor of appreciation to protocol reserve
   * See whitepaper for more information on thee reserve
   **/
  function mintToReserve(uint256 amount, uint256 exchangeRate) external override onlyPool {
      if (amount == 0) {
        return;
      }

      uint256 scaledAmount = amount.wadDiv(exchangeRate);


      _mint(reserve, scaledAmount);
      emit Mint(reserve, amount, exchangeRate);
  }

  /**
   * @dev Supplies appreciation delta to liquidity vault to be used as liquidity for savings
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
          console.log("supplyLiquidityVault 1");
          if (amountDelta <= 10e18) { return; }
          console.log("supplyLiquidityVault 2");
          IRouter(_poolAssetData.getRouter(_underlyingAsset)).redeemNR(
              amountDelta,
              vault,
              asset
          );
      }
  }

  function supply(uint256 amount) internal returns (uint256) {
      ( , uint256 amountBack) = IRouter(_poolAssetData.getRouter(_underlyingAsset)).deposit(
          _underlyingAsset,
          amount,
          0,
          address(this)
      );

      require(amountBack != 0, "Error: Router failed.  Please try again later");

      emit RouterDeposit(
          msg.sender,
          amount
      );

      return amountBack.mul(10**_decimals).div(10**_routerAssetDecimals);
  }

  /**
   * @dev Burns wrapped asset and sends AUST to the underlying asset avaToken savings equivelent
   * Logic to use this function and conditionals is held in Pool
   **/
  function burnToSavings(address account, uint256 amount, address _to, uint256 exchangeRate) external override onlyPool {
      uint256 amountScaled = amount.wadDiv(exchangeRate);
      require(amountScaled != 0, "Error: Invalid burn amount");
      _burn(account, amountScaled);

      ( , uint256 routerExchangeRate) = IExchangeRateData(_poolAssetData.getExchangeRateData(_underlyingAsset)).getInterestData();
      uint256 _toAmount = amount.wadDiv(routerExchangeRate);
      _routerWrapped.safeTransfer(_to, _toAmount);

      emit Burn(account, _to, amount, exchangeRate);
  }

  /**
   * @dev Burns wrapped asset and redeem AUST into underlying asset to receiver
   **/
  function burnAndRedeem(address account, address receiver, address _toAsset, uint256 amount, uint256 exchangeRate) external override onlyPoolOrLiquidationCaller returns (uint256) {
      require(amount != 0, "Error: Burn amount cannot be zero");

      ( , uint256 routerExchangeRate) = IExchangeRateData(_poolAssetData.getExchangeRateData(_underlyingAsset)).getInterestData();

      if (_toAsset == address(0)) {
          _toAsset = _underlyingAsset;
      }
      uint256 amountBack = IRouter(_poolAssetData.getRouter(_underlyingAsset)).redeem(
          amount.mul(10**_routerAssetDecimals).div(10**_decimals).wadDiv(routerExchangeRate),
          receiver,
          _toAsset
      );

      uint256 scaledAmount = amount.wadDiv(exchangeRate);

      _burn(account, scaledAmount);

      emit Burn(account, receiver, amount, exchangeRate);

      return amountBack;
  }

  /// redeem from router to receiver or send underlying/aust to receiver
  /**
   * @dev A mix of burnToSavings and burnAndRedeem
   **/
  function burn(
      address account,
      address receiver,
      uint256 amount,
      uint256 exchangeRate,
      bool redeem
  ) external onlyPoolOrLiquidationCaller {
      require(amount != 0, "Error: Burn amount cannot be zero");

      ( , uint256 routerExchangeRate) = IExchangeRateData(_poolAssetData.getExchangeRateData(_underlyingAsset)).getInterestData();

      if (redeem) {
          address router =  _poolAssetData.getRouter(_underlyingAsset);
          IRouter(router).redeem(
              amount.mul(10**_routerAssetDecimals).div(10**_decimals).wadDiv(routerExchangeRate),
              receiver,
              _underlyingAsset
          );
      } else {
          // to avaTokenS
          uint256 _toAmount = amount.wadDiv(routerExchangeRate);
          _routerWrapped.safeTransfer(receiver, _toAmount);
      }

      uint256 scaledAmount = amount.wadDiv(exchangeRate);

      _burn(account, scaledAmount);

      emit Burn(account, receiver, amount, exchangeRate);
  }

  /**
   * @dev Scaled balance of account
   **/
  function balanceOfScaled(address account) public view override returns (uint256) {
      return super.balanceOf(account);
  }

  // value of borrowers collateral being used against debt
  /**
   * @dev Balance of account as `scaled` * `exchangeRate`
   *
   * Exchange rate is simulated with the last updated interest rate and timestamp delta
   **/
  function balanceOf(address account) public view virtual override returns (uint256) {
      uint256 scaledAmount = super.balanceOf(account);
      uint256 collateralExchangeRate = _poolAssetData.simulateCollateralExchangeRate(_underlyingAsset);
      return scaledAmount.wadMul(collateralExchangeRate);
  }

  function totalScaledSupply() external view override returns (uint256) {
      return super.totalSupply();
  }

  /**
   * @dev Total supply as `scaled` * `exchangeRate`
   *
   * Exchange rate is simulated with the last updated interest rate and timestamp delta
   **/
  function totalSupply() public view virtual override returns (uint256) {
      uint256 collateralExchangeRate = _poolAssetData.simulateCollateralExchangeRate(_underlyingAsset);
      return super.totalSupply().wadMul(collateralExchangeRate);
  }

  // bridging may not be accurately depicted due to off chain events taking place in ddifferent blocks
  // total amount currently available through aUST
  /* function routerTotalScaledSupply() external view returns (uint256) {
      return _routerWrapped.balanceOf(address(this)); //aUST
  } */

  /* function routerTotalScaledSupplyStored() external view returns (uint256) {
      return routerTotalSupply; // stored
  } */

  /* function collateralAddress(address account) external view override returns (address) {
      return _accountCollateralInstances[account];
  } */


}
