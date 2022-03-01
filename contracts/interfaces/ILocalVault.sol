// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILocalVault {

    function vaultOpenAndWrappedAvailable(uint256 underlyingAmount) external view returns (bool);

    function vaultOpenAndUnderlyingAvailable(uint256 wrappedAmount) external view returns (bool);

    function deposit(uint256 _amount, uint256 _minAmountOut, address to) external;

    function redeem(uint256 _amount, address to, address _outAsset) external;

    function redeemNR(uint256 _amount, address to, address _outAsset) external;

}
