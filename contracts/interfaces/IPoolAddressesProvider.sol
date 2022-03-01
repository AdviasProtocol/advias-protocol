//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IPoolAddressesProvider {
  function updatePool(address _pool) external;

  function getPool() external view returns (address);

  function getToken() external view returns (address);

  function updateToken(address token) external;

  function updateRewardsBase(address _rewardsBase) external;

  function getRewardsBase() external view returns (address);

  function updatePriceOracle(address _priceOracle) external;

  function getPriceOracle() external view returns (address);

  function getRewardsTokenFactory() external view returns (address);

  function updateRewardsTokenFactory(address _rewardsTokenFactory) external;

  function updatePoolAssetData(address _poolAssetData) external;

  function getPoolAssetData() external view returns (address);

  function updateCollateralTokenFactory(address _collateralTokenFactory) external;

  function getCollateralTokenFactory() external view returns (address);

  function updateWrappedTokenFactory(address _wrappedTokenFactory) external;

  function getWrappedTokenFactory() external view returns (address);

  function updatePoolFactory(address _poolFactory) external;

  function getPoolFactory() external view returns (address);

  function updateLiquidationCaller(address _liquidationCaller) external;

  function getLiquidationCaller() external view returns (address);

  function updateUST(address _UST) external;

  function getUST() external view returns (address);

  function updateaUST(address _aUST) external;

  function getaUST() external view returns (address);

  function updateSavingsTokenFactory(address _savingsTokenFactory) external;

  function getSavingsTokenFactory() external view returns (address);

  function updateRouterFactory(address _routerFactory) external;

  function getRouterFactory() external view returns (address);

  function updateDebtTokenFactory(address _debtTokenFactory) external;

  function getDebtTokenFactory() external view returns (address);

  function getPoolAdmin() external view returns (address);

  function updatePoolAdmin(address _poolAdmin) external;

  function updateSwap(address _swap) external;

  function getSwap() external view returns (address);

  function updateLiquidityVault(address _liquidityVault) external;

  function getLiquidityVault() external view returns (address);

  function updateAnchorVault(address _anchorVault) external;

  function getAnchorVault() external view returns (address);

  function updateAnchorVaultRouter(address _anchorVaultRouter) external;

  function getAnchorVaultRouter() external view returns (address);

  function updateRouter(address _router) external;

  function getRouter() external view returns (address);

}
