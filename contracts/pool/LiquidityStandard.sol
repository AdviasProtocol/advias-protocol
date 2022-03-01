// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IRouter} from '../interfaces/IRouter.sol';

import {IPoolAddressesProvider} from '../interfaces/IPoolAddressesProvider.sol';
import {ISwapper} from "../interfaces/ISwapper.sol";
import {ILiquidityStandard} from "../interfaces/ILiquidityStandard.sol";
import {IPool} from "../interfaces/IPool.sol";
import {IPoolAssetData} from "../interfaces/IPoolAssetData.sol";
import {WadRayMath} from '../libraries/WadRayMath.sol';

import "hardhat/console.sol";

contract LiquidityStandard is ILiquidityStandard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;
  using WadRayMath for uint256;

  IPool private _pool;
  IPoolAddressesProvider private _addressesProvider;
  uint256 private optimalLiquidityLevel;

  constructor(
      IPoolAddressesProvider addressesProvider,
      uint256 _optimalLiquidityLevel
  ) {
      _addressesProvider = addressesProvider;
      _pool = IPool(_addressesProvider.getPool());
      optimalLiquidityLevel = _optimalLiquidityLevel;
  }

  modifier onlyPool() {
    require(msg.sender == address(_pool), "Error: Only pool can be sender.");
    _;
  }

  modifier onlyPoolAdmin() {
    require(msg.sender == _addressesProvider.getPoolAdmin(), "Error: Only pool admin can be caller.");
    _;
  }


  function updateOptimalLiquidityLevel(uint256 _optimalLiquidityLevel) external onlyPoolAdmin {
      optimalLiquidityLevel = _optimalLiquidityLevel; // 20%
  }



  function supply(address _asset, uint256 amount) external override onlyPool {
      IERC20(_asset).safeTransfer(msg.sender, amount);
  }

  /**
   * @dev Transfers in assets and swaps to an asset
   * @param _fromAsset Asset being transferred in
   * @param _toAsset Asset to swap to
   * @param amount Amount to transfer in
   **/
  function sendInAndSwapTo(address _fromAsset, address _toAsset, uint256 amount) external override onlyPool {
      IERC20(_fromAsset).safeTransferFrom(msg.sender, address(this), amount);
      address swap = _addressesProvider.getSwap();
      ISwapper swapper = ISwapper(swap);
      swapper.swapToken(
          _fromAsset,
          _toAsset,
          amount,
          0,
          address(this)
      );
  }

  // redeems aust to asset up to the optimalLiquidityLevel
  /**
   * @dev Redeems asset from anchor to this address
   * @param asset Asset being transferred in
   * @param wrappedAsset Asset to swap to
   **/
  function liquidityRedeem(address asset, address wrappedAsset) external override {
      uint256 wrappedBalance = IERC20(asset).balanceOf(wrappedAsset);
      uint256 liquidityBalance = IERC20(asset).balanceOf(address(this));
      uint256 wrappedTotalSupply = IERC20(wrappedAsset).totalSupply();
      uint256 totalAvailable = wrappedBalance.add(liquidityBalance);
      if (totalAvailable < wrappedTotalSupply.wadMul(optimalLiquidityLevel)) {
          uint256 redeemAmount = (wrappedTotalSupply.wadMul(optimalLiquidityLevel)).sub(totalAvailable);
          IRouter(_addressesProvider.getRouter()).redeemNR(
              redeemAmount,
              address(this),
              asset
          );
      }
  }

  /// redeems specific amount called by gov
  function liquidityRedeemGov(address asset, uint256 redeemAmount) external onlyPoolAdmin {
      require(IPoolAssetData(_addressesProvider.getPoolAssetData()).getIsSavings(asset), "Error: Cannot redeem to non-savings asset");
      IRouter(_addressesProvider.getRouter()).redeem(
          redeemAmount,
          address(this),
          asset
      );
  }

  // when updating liquidity standard vault
  function migrate(address asset, uint256 amount) external onlyPoolAdmin {
      IERC20(asset).approve(_addressesProvider.getPoolAdmin(), amount);
      IERC20(asset).transfer(_addressesProvider.getPoolAdmin(), amount);
  }

}
