// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// routes to either terra router or protocol vault
interface IRouter {
    // return how much needed to achieve *goalInterestRate* on a deposit
    function getAllotAmountOnSupply(
        uint256 amountAdded,
        address supplyWrapped,
        uint256 goalInterestRate,
        address debtWrapped,
        uint256 supplyInterestRate,
        uint256 minSupplyRequirementAmount,
        uint256 decimals
    ) external view returns (uint256);

    // return how much needed to achieve *goalInterestRate* on a redeem
    function getAllotAmountOnRedeem(
        uint256 amountToWithdraw,
        address supplyWrapped,
        uint256 goalInterestRate,
        address debtWrapped,
        uint256 supplyInterestRate,
        uint256 minRedeemRequirementAmount,
        uint256 decimals
    ) external view returns (uint256);

    function deposit(address asset, uint256 _amount, uint256 _minAmountOut, address to) external returns (bool, uint256);

    function redeem(uint256 _amount, address to, address _outAsset) external returns (uint256);

    function redeemNR(uint256 _amount, address to, address _outAsset) external returns (uint256);

    function _underlyingAsset() external view returns (address);

    function _wrappedAsset() external view returns (address);

    function depositAmountMinusFees(uint256 _amount) external view  returns (uint256);

}
