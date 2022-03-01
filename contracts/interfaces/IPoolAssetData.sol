//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

/* import {PoolStorage} from './PoolStorage.sol'; */

interface IPoolAssetData {
  function getPoolAssetsList() external view returns (address[] memory);

  function getLastUpdatedTimestamp(address asset) external view returns (uint256);

  /* function getIsUST(address asset) external view returns (bool); */

  function getRouter(address asset) external view returns (address);

  function getDepositsSuppliedExchangeRate(address asset) external view returns (uint256);

  /* function getRouter(address asset) external view returns (address); */

  function getTotalDepositsLendable(address asset) external view returns (uint256);

  /* function getLendableExchangeRate(address asset) external view returns (uint256); */

  function getCollateralExchangeRate(address asset) external view returns (uint256);

  function getCollateralWrappedAsset(address asset) external view returns (address);

  function getDebtWrappedAsset(address asset) external view returns (address);

  function getDepositWrappedAsset(address asset) external view returns (address);

  function getRouterExchangeRate(address asset) external view returns (uint256);

  function getBorrowExchangeRate(address asset) external view returns (uint256);

  function getExchangeRateData(address asset) external view returns (address);

  function getIsCollateral(address asset) external view returns (bool);

  function getIsDebt(address asset) external view returns (bool);

  function getIsSavings(address asset) external view returns (bool);

  function getIsOn(address asset) external view returns (bool);

  function simulateBorrowExchangeRate(address asset) external view returns (uint256);

  function simulateLendableTotalSupply(address asset) external view returns (uint256);

  function simulateCollateralExchangeRate(address asset) external view returns (uint256);

  function simulateDepositsSuppliedExchangeRate(address asset) external view returns (uint256);

  function simulateOverallExchangeRate(address asset) external view returns (uint256);

  function getDecimals(address asset) external view returns (uint256);

  function getMaxCtdLiquidationThreshold(address asset) external view returns (uint256);

  function getLiquidationThreshold(address asset) external view returns (uint256);

  function getIsStable(address asset) external view returns (bool);

  function getUserData(
      address account
  ) external view returns (
      uint256,
      uint256,
      uint256,
      uint256,
      uint256,
      uint256,
      uint256
  );

}
