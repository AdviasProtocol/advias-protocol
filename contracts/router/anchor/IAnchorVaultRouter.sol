// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAnchorVaultRouter {
    function deposit(address asset, uint256 _amount, uint256 _minAmountOut, address to) external returns (uint256);

    function redeem(address asset, uint256 _amount, address to) external returns (uint256);

    function redeemNR(address asset, uint256 _amount, address to) external returns (uint256);
}
