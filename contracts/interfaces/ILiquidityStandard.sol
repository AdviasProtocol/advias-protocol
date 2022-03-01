// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILiquidityStandard {

  function supply(address _asset, uint256 amount) external;

  function sendInAndSwapTo(address _fromAsset, address _toAsset, uint256 amount) external;

  function liquidityRedeem(address asset, address wrappedAsset) external;

}
