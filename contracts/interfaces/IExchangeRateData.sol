// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IExchangeRateData {
  function getInterestDataUpdated() external returns (uint256, uint256);

  function getInterestData() external view returns (uint256, uint256);

  function getInterestData(address asset) external view returns (uint256, uint256);

}
