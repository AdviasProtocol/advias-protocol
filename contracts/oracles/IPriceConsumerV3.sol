// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPriceConsumerV3 {
    function getLatestPrice(address asset) external view returns (int);

    function decimals(address asset) external view returns (uint8);

}
