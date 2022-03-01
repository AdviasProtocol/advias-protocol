// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IConversionPool {
    function deposit(uint256 _amount) external;

    function deposit(uint256 _amount, uint256 _minAmountOut) external;

    function redeem(uint256 _amount) external;

    function redeem(uint256 _amount, uint256 _minAmountOut) external;

    function deposit(uint256 _amount, uint256 _minAmountOut, address to) external;

    function redeem(uint256 _amount, address to) external;

    function feeder() external returns (address);

    function inputToken() external returns (address);

    function outputToken() external returns (address);

}
