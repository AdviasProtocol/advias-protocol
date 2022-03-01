//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolLogic} from './PoolLogic.sol';
import {IPoolAssetData} from '../interfaces/IPoolAssetData.sol';

import {PoolStorage} from '../pool/PoolStorage.sol';
import {ICollateralToken} from '../interfaces/ICollateralToken.sol';
import {IAvaToken} from '../interfaces/IAvaToken.sol';
import {IDebtToken} from '../interfaces/IDebtToken.sol';

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {WadRayMath} from './WadRayMath.sol';

// import "hardhat/console.sol";

// actual
/**
 * @title General library
 * @author Advias
 * @dev General protool logic
 **/

library General {
    using SafeMath for uint256;
    using WadRayMath for uint256;

    struct UserDataParams {
      address account;
      uint256 totalDebtValueInEth;
      uint256 totalCollateralValueInEth;
      address priceOracle;
      uint256 avgMaxCtdLiquidationThreshold;
      uint256 avgLiquidationThreshold;
      uint256 decimals;
      uint256 debt;
      uint256 collateral;
      uint256 maxCtdLiquidationThreshold;
      uint256 liquidationThreshold;
      uint256 debtValue;
      uint256 collateralValue;
      uint256 avgLtv;
    }

    /* function getUserData(
        mapping(address => PoolStorage.PoolAsset) storage poolAssets,
        mapping(uint256 => address) storage poolAssetsList,
        uint256 poolAssetsCount,
        address account,
        address priceOracle
    ) internal view returns (
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256
    ) {
        UserDataParams memory params;
        params.account = account;
        params.priceOracle = priceOracle;


        for (uint256 i = 0; i < poolAssetsCount; i++) {
            address currentPoolAssetAddress = poolAssetsList[i];
            PoolStorage.PoolAsset storage currentPoolAsset = poolAssets[currentPoolAssetAddress];

            params.decimals = currentPoolAsset.decimals;

            if (currentPoolAsset.isDebt){
                params.debt = IERC20(currentPoolAsset.debtWrappedAsset).balanceOf(params.account);
            }

            if (currentPoolAsset.isCollateral){
                params.collateral = IERC20(currentPoolAsset.collateralAssetWrapped).balanceOf(params.account);
            }

            if (params.debt == 0 && params.collateral == 0) {
                continue;
            }

            uint256 debtValue = PoolLogic.getValueInEth(
                currentPoolAssetAddress,
                params.decimals,
                params.debt,
                params.priceOracle
            );
            params.totalDebtValueInEth += debtValue;

            // stable liquidation threshold?????

            uint256 collateralValue = PoolLogic.getValueInEth(
                currentPoolAssetAddress,
                params.decimals,
                params.collateral,
                params.priceOracle
            );
            params.totalCollateralValueInEth += collateralValue;

            params.maxCtdLiquidationThreshold = currentPoolAsset.maxCtdLiquidationThreshold;

            params.avgMaxCtdLiquidationThreshold = params.avgMaxCtdLiquidationThreshold.add(
                collateralValue.wadDiv(params.maxCtdLiquidationThreshold)
            );

            params.liquidationThreshold = currentPoolAsset.liquidationThreshold;

            params.avgLiquidationThreshold = params.avgLiquidationThreshold.add(
                debtValue.mul(params.liquidationThreshold)
            );

        }

        params.avgLiquidationThreshold = params.avgLiquidationThreshold.div(params.totalCollateralValueInEth);

        // 1.06 =  254,400 / 240,000
        uint256 avgMaxCtdLiquidationThresholdSpread = params.avgMaxCtdLiquidationThreshold.div(params.totalCollateralValueInEth);
        // 1.09 = 240,000 / 220,000
        uint256 averageMaxCtd = params.totalCollateralValueInEth.div(params.totalDebtValueInEth);
        // max params.collateral scale
        // .97 = 1.06 / 1.09
        uint256 collateralHealth = avgMaxCtdLiquidationThresholdSpread.wadDiv(averageMaxCtd);


        // min params.collateral scale
        // .87272 = 240,000 * .8 / 220,000
        uint256 debtHealth = params.totalDebtValueInEth == 0 ? ~uint256(0) : (params.totalCollateralValueInEth.wadMul(params.avgLiquidationThreshold)).wadDiv(params.totalDebtValueInEth);

        return (
          params.totalCollateralValueInEth,
          params.totalDebtValueInEth,
          averageMaxCtd,
          params.avgLiquidationThreshold,
          collateralHealth,
          debtHealth
        );

    } */

    function getUserData(
        address[] memory poolAssetsList,
        address account,
        address priceOracle,
        address poolAssetData
    ) internal view returns (
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256
    ) {
        UserDataParams memory params;
        params.account = account;
        params.priceOracle = priceOracle;
        // console.log("General getUserData start");


        for (uint256 i = 0; i < poolAssetsList.length; i++) {
            params.debt = 0;
            params.collateral = 0;
            address currentPoolAssetAddress = poolAssetsList[i];

            params.decimals = IPoolAssetData(poolAssetData).getDecimals(currentPoolAssetAddress);

            if (IPoolAssetData(poolAssetData).getIsDebt(currentPoolAssetAddress)){
                params.debt = IERC20(IPoolAssetData(poolAssetData).getDebtWrappedAsset(currentPoolAssetAddress)).balanceOf(params.account);
            }

            if (IPoolAssetData(poolAssetData).getIsCollateral(currentPoolAssetAddress)){
                params.collateral = IERC20(IPoolAssetData(poolAssetData).getCollateralWrappedAsset(currentPoolAssetAddress)).balanceOf(params.account);
            }

            if (params.debt == 0 && params.collateral == 0) {
                // console.log("Both are zero");

                continue;
            }

            uint256 debtValue = PoolLogic.getValueInEth(
                currentPoolAssetAddress,
                params.decimals,
                params.debt,
                params.priceOracle
            );
            params.totalDebtValueInEth += debtValue;

            // stable liquidation threshold?????

            uint256 collateralValue = PoolLogic.getValueInEth(
                currentPoolAssetAddress,
                params.decimals,
                params.collateral,
                params.priceOracle
            );
            params.totalCollateralValueInEth += collateralValue;

            params.maxCtdLiquidationThreshold = IPoolAssetData(poolAssetData).getMaxCtdLiquidationThreshold(currentPoolAssetAddress);

            if (params.collateral != 0) {
                // console.log("General getUserData collateralValue", collateralValue);
                // console.log("General getUserData collateral", params.collateral);

                // x == 1000 = 1220 / 1.22
                params.avgMaxCtdLiquidationThreshold = params.avgMaxCtdLiquidationThreshold.add(
                    collateralValue.wadDiv(params.maxCtdLiquidationThreshold)
                );
            }

            params.avgLtv = collateralValue > 0 ? params.avgLtv.div(collateralValue) : 0;
            params.liquidationThreshold = IPoolAssetData(poolAssetData).getLiquidationThreshold(currentPoolAssetAddress);

            if (params.debt != 0) {
                params.avgLiquidationThreshold = params.avgLiquidationThreshold.add(
                    debtValue.wadDiv(params.liquidationThreshold)
                );
            }

        }

        params.avgLtv = params.totalCollateralValueInEth > 0 ? params.avgLtv.div(params.totalCollateralValueInEth) : 0;
        // console.log("General getUserData avgLtv", params.avgLtv);

        // console.log("General getUserData params.avgMaxCtdLiquidationThreshold", params.avgMaxCtdLiquidationThreshold);

        // 1.22 = 1220 / 1000
        uint256 averageMaxCtd = params.totalCollateralValueInEth > 0 ? params.totalCollateralValueInEth.wadDiv(params.avgMaxCtdLiquidationThreshold) : 0;

        // console.log("General getUserData averageMaxCtd", averageMaxCtd);

        uint256 overallCtd = params.totalDebtValueInEth > 0 ? params.totalCollateralValueInEth.wadDiv(params.totalDebtValueInEth) : 0;
        // console.log("General getUserData overallCtd", overallCtd);

        uint256 collateralHealth;
        if (averageMaxCtd == 0 || overallCtd == 0) {
            collateralHealth = ~uint256(0);
        } else {
            collateralHealth = averageMaxCtd.wadDiv(overallCtd);
        }
        /* uint256 collateralHealth = averageMaxCtd.wadDiv(overallCtd); */
        // console.log("General getUserData collateralHealth", collateralHealth);

        // min params.collateral scale
        // .87272 = 240,000 * .8 / 220,000
        uint256 debtHealth = params.totalDebtValueInEth == 0 ? ~uint256(0) : (params.totalCollateralValueInEth.wadDiv(params.avgLiquidationThreshold));
        /* uint256 debtHealth = params.totalDebtValueInEth == 0 ? ~uint256(0) : (params.totalCollateralValueInEth.wadMul(params.avgLiquidationThreshold)).wadDiv(params.totalDebtValueInEth); */

        return (
          params.totalCollateralValueInEth,
          params.totalDebtValueInEth,
          averageMaxCtd, // max can be
          params.avgMaxCtdLiquidationThreshold, // max collateral can be
          params.avgLiquidationThreshold,
          collateralHealth,
          debtHealth
        );

    }

}
