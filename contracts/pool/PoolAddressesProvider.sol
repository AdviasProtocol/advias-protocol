//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {IPoolAddressesProvider} from '../interfaces/IPoolAddressesProvider.sol';

/**
 * @title PoolAddressesProvider
 * @author Advias
 * @title Stores protocols contracts for retrieval
 */
contract PoolAddressesProvider is IPoolAddressesProvider {
  address private pool;
  address private poolFactory;
  address private collateralTokenFactory;
  address private wrappedTokenFactory;
  address private savingsTokenFactory;
  address private routerFactory;
  address private debtTokenFactory;
  address private rewardsTokenFactory;
  address private token; // advias
  address private poolAdmin;
  address private poolAssetData;
  address private rewardsBase;
  address private priceOracle;
  address private swap;
  address private liquidationCaller;
  address private UST;
  address private aUST;
  address private liquidityVault;
  address private anchorVault;
  address private anchorVaultRouter;
  address private router;

  constructor() {
      _updatePoolAdmin(msg.sender);
  }

  modifier onlyPoolAdmin() {
      require(msg.sender == poolAdmin);
      _;
  }

  function updatePool(address _pool) external override {
      pool = _pool;
  }

  function getPool() external view override returns (address) {
      return pool;
  }

  function getToken() external view override returns (address) {
      return pool;
  }

  function updateToken(address _token) external override {
      token = _token;
  }

  function updateRewardsBase(address _rewardsBase) external override onlyPoolAdmin {
      rewardsBase = _rewardsBase;
  }

  function getRewardsBase() external view override returns (address) {
      return rewardsBase;
  }

  function updatePriceOracle(address _priceOracle) external override onlyPoolAdmin {
      priceOracle = _priceOracle;
  }

  function getPriceOracle() external view override returns (address) {
      return priceOracle;
  }

  function getRewardsTokenFactory() external view override returns (address) {
      return rewardsTokenFactory;
  }

  function updateRewardsTokenFactory(address _rewardsTokenFactory) external override onlyPoolAdmin {
      rewardsTokenFactory = _rewardsTokenFactory;
  }

  function updatePoolAssetData(address _poolAssetData) external override onlyPoolAdmin {
      poolAssetData = _poolAssetData;
  }

  function getPoolAssetData() external view override returns (address) {
      return poolAssetData;
  }

  function updateCollateralTokenFactory(address _collateralTokenFactory) external override onlyPoolAdmin {
      collateralTokenFactory = _collateralTokenFactory;
  }

  function getCollateralTokenFactory() external view override returns (address) {
      return collateralTokenFactory;
  }

  function updateWrappedTokenFactory(address _wrappedTokenFactory) external override onlyPoolAdmin {
      wrappedTokenFactory = _wrappedTokenFactory;
  }

  function getWrappedTokenFactory() external view override returns (address) {
      return wrappedTokenFactory;
  }

  function updatePoolFactory(address _poolFactory) external override onlyPoolAdmin {
      poolFactory = _poolFactory;
  }

  function getPoolFactory() external view override returns (address) {
      return poolFactory;
  }

  function updateLiquidationCaller(address _liquidationCaller) external override onlyPoolAdmin {
      liquidationCaller = _liquidationCaller;
  }

  function getLiquidationCaller() external view override returns (address) {
      return liquidationCaller;
  }

  function updateUST(address _UST) external override onlyPoolAdmin {
      UST = _UST;
  }

  function getUST() external view override returns (address) {
      return UST;
  }

  function updateaUST(address _aUST) external override onlyPoolAdmin {
      aUST = _aUST;
  }

  function getaUST() external view override returns (address) {
      return aUST;
  }

  function updateSavingsTokenFactory(address _savingsTokenFactory) external override onlyPoolAdmin {
      savingsTokenFactory = _savingsTokenFactory;
  }

  function getSavingsTokenFactory() external view override returns (address) {
      return savingsTokenFactory;
  }

  function updateRouterFactory(address _routerFactory) external override onlyPoolAdmin {
      routerFactory = _routerFactory;
  }

  function getRouterFactory() external view override returns (address) {
      return routerFactory;
  }

  function updateDebtTokenFactory(address _debtTokenFactory) external override onlyPoolAdmin {
      debtTokenFactory = _debtTokenFactory;
  }

  function getDebtTokenFactory() external view override returns (address) {
      return debtTokenFactory;
  }

  function getPoolAdmin() external view override returns (address) {
      return poolAdmin;
  }

  function updatePoolAdmin(address _poolAdmin) public override onlyPoolAdmin {
      _updatePoolAdmin(_poolAdmin);
  }

  function _updatePoolAdmin(address _poolAdmin) internal {
      poolAdmin = _poolAdmin;
  }

  function updateSwap(address _swap) external override onlyPoolAdmin {
      swap = _swap;
  }

  function getSwap() external view override returns (address) {
      return swap;
  }

  function updateLiquidityVault(address _liquidityVault) external override onlyPoolAdmin {
      liquidityVault = _liquidityVault;
  }

  function getLiquidityVault() external view override returns (address) {
      return liquidityVault;
  }

  function updateAnchorVault(address _anchorVault) external override onlyPoolAdmin {
      anchorVault = _anchorVault;
  }

  function getAnchorVault() external view override returns (address) {
      return anchorVault;
  }

  function updateAnchorVaultRouter(address _anchorVaultRouter) external override onlyPoolAdmin {
      anchorVaultRouter = _anchorVaultRouter;
  }

  function getAnchorVaultRouter() external view override returns (address) {
      return anchorVaultRouter;
  }

  function updateRouter(address _router) external override onlyPoolAdmin {
      router = _router;
  }

  function getRouter() external view override returns (address) {
      return router;
  }

}
