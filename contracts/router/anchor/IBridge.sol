// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBridge {

    function wrapped() external view returns (address);

    function deposit(address _fromAsset, uint256 _amount, uint256 _minAmountOut, address to) external returns (uint256);

    function depositAmountMinusFees(uint256 amount) external view returns (uint256);

    function redeem(address _toAsset, uint256 _amount, address to) external returns (uint256);

    function redeemNR(address _toAsset, uint256 _amount, address to) external returns (uint256);

    function redeemAmountMinusFees(uint256 amount) external view returns (uint256);

    function getBridgeFee() external view returns (uint256);
    function getSwapFee() external view returns (uint256);
    function getTax() external view returns (uint256);

}
