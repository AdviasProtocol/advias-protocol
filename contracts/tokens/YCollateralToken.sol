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
contract YCollateralToken is ERC20, ICollateralToken {
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

  function initRouter() public override {
      return;
  }

  modifier onlyPool() {
    require(msg.sender == address(_pool), "Error: Only pool can be sender.");
    _;
  }

  modifier onlyPoolOrLiquidationCaller() {
    require(msg.sender == address(_pool) || msg.sender == ADDRESSES_PROVIDER.getLiquidationCaller(), "Error: Only pool can be sender.");
    _;
  }

  /**
   * @dev Mints avasTokenC as `amount` / `exchangeRate` and supplies `amount` to Anchor
   **/
  function mint(address account, uint256 amount, uint256 exchangeRate, bool supply_) external override onlyPool returns (uint256, uint256) {
      _mint(account, amount);

      emit Mint(account, amount, exchangeRate);

      return (amount, amount);
  }

  function mintToReserve(uint256 amount, uint256 exchangeRate) external override onlyPool {
      return;
  }

  function supplyLiquidityVault(address asset, address vault, uint256 bufferFactor) external override onlyPool {
      return;
  }

  /**
   * @dev Burns wrapped asset and sends AUST to the underlying asset avaToken savings equivelent
   * Logic to use this function and conditionals is held in Pool
   **/
  function burnToSavings(address account, uint256 amount, address _to, uint256 exchangeRate) external override onlyPool {
      require(amount != 0, "Error: Invalid burn amount");
      _burn(account, amount);

      IERC20(_underlyingAsset).safeTransfer(_to, amount);

      emit Burn(account, _to, amount, 0);
  }

  /**
   * @dev Burns wrapped asset and redeem AUST into underlying asset to receiver
   **/
  function burnAndRedeem(address account, address receiver, address _toAsset, uint256 amount, uint256 exchangeRate) external override onlyPoolOrLiquidationCaller returns (uint256) {
      require(amount != 0, "Error: Burn amount cannot be zero");

      IERC20(_underlyingAsset).safeTransfer(receiver, amount);

      _burn(account, amount);

      emit Burn(account, receiver, amount, 0);

      return amount;
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
      return super.balanceOf(account);
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
      return super.totalSupply();  
  }

}
