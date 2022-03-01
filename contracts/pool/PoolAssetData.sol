//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;


import {IPoolAddressesProvider} from '../interfaces/IPoolAddressesProvider.sol';
import {PoolStorage} from './PoolStorage.sol';
import {IPool} from '../interfaces/IPool.sol';
import {Pool} from './Pool.sol';
import {IExchangeRateData} from '../interfaces/IExchangeRateData.sol';
import {General} from '../libraries/General.sol';

import {IPoolAssetData} from '../interfaces/IPoolAssetData.sol';
import {PoolLogic} from '../libraries/PoolLogic.sol';
import {WadRayMath} from '../libraries/WadRayMath.sol';
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAvaToken} from '../interfaces/IAvaToken.sol';

import "hardhat/console.sol";

/**
 * @title PoolAssetData
 * @author Advias
 * @title Protocol data retriever
 */
contract PoolAssetData is IPoolAssetData {
  using WadRayMath for uint256;
  IPoolAddressesProvider internal addressesProvider;

  constructor(IPoolAddressesProvider _provider) {
    addressesProvider = _provider;
  }

  function getLastUpdatedTimestamp(address asset) external view override returns (uint256) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      return poolAsset.lastUpdatedTimestamp;
  }

  /* function getIsUST(address asset) external view override returns (bool) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      return poolAsset.isUST;
  } */

  function getRouter(address asset) external view override returns (address) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      return poolAsset.router;
  }

  function getDepositsSuppliedExchangeRate(address asset) external view override returns (uint256) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      return poolAsset.depositsSuppliedExchangeRate;
  }

  function getTotalDepositsLendable(address asset) external view override returns (uint256) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      return poolAsset.totalDepositsLendable;
  }

  function getDecimals(address asset) external view override returns (uint256) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      return poolAsset.decimals;
  }

  function getMaxCtdLiquidationThreshold(address asset) external view override returns (uint256) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      return poolAsset.maxCtdLiquidationThreshold;
  }

  function getCtd(address asset) external view returns (uint256) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      return poolAsset.ctd;
  }

  function getLtv(address asset) external view returns (uint256) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      return poolAsset.ltv;
  }

  function getLiquidationThreshold(address asset) external view override returns (uint256) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      return poolAsset.liquidationThreshold;
  }

  function getCollateralExchangeRate(address asset) external view override returns (uint256) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      return poolAsset.collateralExchangeRate;
  }

  function getCollateralInterestRate(address asset) external view returns (uint256) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      (
        ,
        uint256 routerInterestRate
      ) = PoolLogic._getInterestData(poolAsset.exchangeRateData);
      return routerInterestRate.wadMul(poolAsset.collateralInterestRateFactor);
  }


  function getCollateralWrappedAsset(address asset) external view override returns (address) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      return poolAsset.collateralAssetWrapped;
  }

  function getCollateralInterestRateFactor(address asset) external view returns (uint256) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      return poolAsset.collateralInterestRateFactor;
  }

  function getDebtWrappedAsset(address asset) external view override returns (address) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      return poolAsset.debtWrappedAsset;
  }

  function getDepositWrappedAsset(address asset) external view override returns (address) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      return poolAsset.wrapped;
  }

  function getRouterExchangeRate(address asset) external view override returns (uint256) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      return poolAsset.routerExchangeRate;
  }

  function getIsCollateral(address asset) public view override returns (bool) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      return poolAsset.isCollateral;
  }

  function getIsDebt(address asset) public view override returns (bool) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      return poolAsset.isDebt;
  }

  function getIsSavings(address asset) public view override returns (bool) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      return poolAsset.isSavings;
  }

  function getIsOn(address asset) external view override returns (bool) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      return poolAsset.on;
  }

  function getOverallExchangeRate(address asset) external view returns (uint256) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      return poolAsset.overallExchangeRate;
  }

  function getBorrowExchangeRate(address asset) external view override returns (uint256) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      return poolAsset.borrowExchangeRate;
  }

  function getBorrowInterestRate(address asset) external view returns (uint256) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      return poolAsset.borrowInterestRate;
  }

  function getExchangeRateData(address asset) external view override returns (address) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      return poolAsset.exchangeRateData;
  }

  function getPoolAssetsList() public view override returns (address[] memory) {
      Pool pool = Pool(addressesProvider.getPool());
      uint256 poolAssetsCount = pool.poolAssetsCount();
      address[] memory underlying = new address[](poolAssetsCount);
      for (uint256 i = 0; i < poolAssetsCount; i++) {
          underlying[i] = pool.poolAssetsList(i);
      }
      return underlying;
  }

  function getSavingsAssetsList() external view returns (address[] memory) {
      Pool pool = Pool(addressesProvider.getPool());
      uint256 savingsAssetsCount = pool.savingsAssetsCount();
      address[] memory underlying = new address[](savingsAssetsCount);
      for (uint256 i = 0; i < savingsAssetsCount; i++) {
          if (!getIsSavings(underlying[i])) { continue; }
          underlying[i] = pool.poolAssetsList(i);
      }
      return underlying;
  }

  function getCollateralAssetsList() external view returns (address[] memory) {
      Pool pool = Pool(addressesProvider.getPool());
      uint256 collateralAssetsCount = pool.collateralAssetsCount();
      address[] memory underlying = new address[](collateralAssetsCount);
      for (uint256 i = 0; i < collateralAssetsCount; i++) {
          if (!getIsCollateral(underlying[i])) { continue; }
          underlying[i] = pool.poolAssetsList(i);
      }
      return underlying;
  }

  function getInterestData(address asset) public view returns (uint256, uint256) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      (
        uint256 routerExchangeRate,
        uint256 routerInterestRate
      ) = PoolLogic._getInterestData(poolAsset.exchangeRateData);
      return (routerExchangeRate, routerInterestRate);
  }

  // calculations data
  function simulateBorrowExchangeRate(address asset) public view override returns (uint256) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      (
        uint256 routerExchangeRate,
      ) = PoolLogic._getInterestData(poolAsset.exchangeRateData);

      return PoolLogic.simulateBorrowExchangeRate(
          routerExchangeRate,
          poolAsset.routerExchangeRate,
          poolAsset.debtInterestRateFactor,
          poolAsset.borrowExchangeRate
      );
  }

  function simulateOverallExchangeRate(address asset) external view override returns (uint256) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      (
        uint256 routerExchangeRate,
      ) = PoolLogic._getInterestData(poolAsset.exchangeRateData);

      return PoolLogic.simulateOverallExchangeRate(
          poolAsset.overallExchangeRate,
          routerExchangeRate,
          poolAsset.routerExchangeRate,
          poolAsset.isSavings,
          poolAsset.debtWrappedAsset,
          poolAsset.totalDepositsLendable,
          poolAsset.borrowExchangeRate,
          simulateBorrowExchangeRate(asset),
          poolAsset.depositsSuppliedExchangeRate,
          simulateDepositsSuppliedExchangeRate(asset),
          poolAsset.wrapped,
          poolAsset.reserveFactor
      );

  }


  function simulateLendableTotalSupply(address asset) public view override returns (uint256) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      (
        uint256 routerExchangeRate,
      ) = PoolLogic._getInterestData(poolAsset.exchangeRateData);

      return PoolLogic.simulateLendableTotalSupply(
          poolAsset.debtWrappedAsset,
          simulateBorrowExchangeRate(asset),
          poolAsset.totalDepositsLendable,
          routerExchangeRate,
          poolAsset.routerExchangeRate,
          poolAsset.borrowExchangeRate
      );
  }

  function simulateCollateralExchangeRate(address asset) public view override returns (uint256) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      (
        uint256 routerExchangeRate,
      ) = PoolLogic._getInterestData(poolAsset.exchangeRateData);

      return PoolLogic.simulateCollateralExchangeRate(
          routerExchangeRate,
          poolAsset.routerExchangeRate,
          poolAsset.collateralExchangeRate,
          poolAsset.collateralInterestRateFactor,
          poolAsset.reserveFactor
      );
  }

  function simulateDepositsSuppliedExchangeRate(address asset) public view override returns (uint256) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      (
        uint256 routerExchangeRate,
      ) = PoolLogic._getInterestData(poolAsset.exchangeRateData);

      return PoolLogic.simulateDepositsSuppliedExchangeRate(
          routerExchangeRate,
          poolAsset.routerExchangeRate,
          poolAsset.depositsSuppliedExchangeRate,
          poolAsset.depositsSuppliedInterestRateFactor
      );
  }


  function getAssetSavingsInterestRate(address asset) external view returns (uint256) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      address wrapped = poolAsset.wrapped;
      uint256 borrowInterestRate = poolAsset.borrowInterestRate;
      uint256 savingsRouterRate = poolAsset.depositsSuppliedInterestRate;
      if (!poolAsset.isDebt) {
          return poolAsset.depositsSuppliedInterestRate;
      }
      uint256 totalDebt = IERC20(poolAsset.debtWrappedAsset).totalSupply();
      uint256 lendTotalSupply = IAvaToken(wrapped).lendableTotalSupply();
      if (totalDebt == 0 || lendTotalSupply == 0) {
          return poolAsset.depositsSuppliedInterestRate.wadMul(poolAsset.debtInterestRateFactor);
      }

      uint256 savingsRouterTotalSupply = IAvaToken(wrapped).routerSuppliedTotalSupply();

      return PoolLogic.getAssetSavingsInterestRate(
          wrapped,
          borrowInterestRate,
          savingsRouterRate,
          totalDebt,
          lendTotalSupply,
          savingsRouterTotalSupply
      );
  }

  function getIsStable(address asset) external view override returns (bool) {
      PoolStorage.PoolAsset memory poolAsset = IPool(addressesProvider.getPool()).getPoolAssetData(asset);
      return poolAsset.isStable;
  }

  struct getUserDataParams {
    address account;
  }
  /**
   * @dev Retrieves a users overall data
   * This is mainly used to check if a borrower can be liquidated
   **/
  function getUserData(
      address account
  ) external view override returns (
      uint256,
      uint256,
      uint256,
      uint256,
      uint256,
      uint256,
      uint256
  ) {
      getUserDataParams memory params;
      params.account = account;
      (
          uint256 totalCollateralValueInEth,
          uint256 totalDebtValueInEth,
          uint256 averageCtd,
          uint256 avgMaxCtdLiquidationThreshold,
          uint256 avgLiquidationThreshold,
          uint256 collateralHealth,
          uint256 debtHealth
      ) = General.getUserData(
          getPoolAssetsList(),
          params.account,
          addressesProvider.getPriceOracle(),
          address(this)
      );
      return (
          totalCollateralValueInEth,
          totalDebtValueInEth,
          averageCtd,
          avgMaxCtdLiquidationThreshold,
          avgLiquidationThreshold,
          collateralHealth,
          debtHealth
      );
  }

}
