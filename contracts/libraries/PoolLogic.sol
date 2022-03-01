//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {PoolStorage} from '../pool/PoolStorage.sol';
import {ICollateralToken} from '../interfaces/ICollateralToken.sol';
import {IAvaToken} from '../interfaces/IAvaToken.sol';
import {IDebtToken} from '../interfaces/IDebtToken.sol';
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {WadRayMath} from './WadRayMath.sol';
import {IExchangeRateData} from '../interfaces/IExchangeRateData.sol';
import {IPriceConsumerV3} from '../oracles/IPriceConsumerV3.sol';

// import "hardhat/console.sol";

/**
 * @title PoolLogic library
 * @author Advias
 * @dev Holds the protocols Pool logic functions
 **/

library PoolLogic {
    using SafeMath for uint256;
    using WadRayMath for uint256;

    uint256 constant ONE_YR = 31536000;
    uint256 constant ONE_FACTOR = 1e18;

    function initCollateralToken(
        PoolStorage.PoolAsset storage collateralAsset,
        address asset,
        address collateralAssetWrapped,
        address router,
        address exchangeRateData,
        uint256 routerMinSupplyRedeemAmount,
        uint256 routerMaxSupplyRedeemAmount,
        uint256 collateralInterestRateFactor,
        uint256 ctd,
        bool isRoutable
    ) external {
        (
          uint256 routerExchangeRate,
          uint256 routerInterestRate
        ) = _getInterestData(exchangeRateData);

        collateralAsset.asset = asset; // ust
        collateralAsset.decimals = IERC20Metadata(asset).decimals();
        collateralAsset.collateralExchangeRate = 1e18;
        collateralAsset.collateralInterestRateFactor = collateralInterestRateFactor;
        collateralAsset.collateralAssetWrapped = collateralAssetWrapped;
        collateralAsset.router = router;
        collateralAsset.exchangeRateData = exchangeRateData; //address to router to send collateral to anchor
        collateralAsset.routerExchangeRate = routerExchangeRate; // storeed byways of anchor exchangeRateFeeder
        collateralAsset.routerInterestRate = routerInterestRate; // eestimated by exchangeRateFeeder
        collateralAsset.collateralRouterMinSupplyRedeemAmount = routerMinSupplyRedeemAmount*(10**collateralAsset.decimals); // min amount collateralRouterMinSupplyRedeemAmount allows


        collateralAsset.routerMaxSupplyRedeemAmount = routerMaxSupplyRedeemAmount*(10**collateralAsset.decimals);
        collateralAsset.isCollateral = true;
        collateralAsset.isSavings = false; // collateral is always called first if there is, will update to true if we init savings and debt asset
        collateralAsset.reserveFactor = uint256(100000000000000000); // 10%
        collateralAsset.on = true;
        collateralAsset.lastUpdatedTimestamp = block.timestamp;
        /* collateralAsset.liquidationBonusFactorOnSpread = uint256(800000000000000000); // 10% */
        collateralAsset.liquidationBonusFactor = uint256(200000000000000000); // 20%
        /* collateralAsset.collateralLiquidityBufferFactor = uint256(50000000000000000); // 10% */
        collateralAsset.ctd = ctd; // 125% collateral to debt ratio
        collateralAsset.isRoutable = isRoutable;

        collateralAsset.maxCtdLiquidationThreshold = uint256(1e18).wadMul(uint256(1e18)).add((routerInterestRate.wadMul(collateralInterestRateFactor)).div(ONE_YR)).wadPow(ONE_YR);
        collateralAsset.isStable = true;
        collateralAsset.selfLiquidationPremium = uint256(40000000000000000); // 4%
        // console.log(" Pool Logic initCollateralToken maxCtdLiquidationThreshold", collateralAsset.maxCtdLiquidationThreshold);

        collateralAsset.repayCooldownTime = uint256(500); // unix_per_block*15
    }

    function initSavingsToken(
        PoolStorage.PoolAsset storage poolAsset,
        address asset,
        address wrapped,
        address router,
        address exchangeRateData,
        uint256 routerMinSupplyRedeemAmount,
        uint256 depositsSuppliedInterestRateFactor,
        bool isRoutable
    ) internal {
        (
          uint256 routerExchangeRate,
          uint256 routerInterestRate
        ) = _getInterestData(exchangeRateData);


        poolAsset.isSavings = true;
        poolAsset.asset = asset;
        poolAsset.decimals = IERC20Metadata(asset).decimals();
        poolAsset.wrapped = wrapped;
        poolAsset.reserveFactor = uint256(100000000000000000); // 10%
        poolAsset.router = router;
        poolAsset.depositsSuppliedExchangeRate = uint256(1e18);
        poolAsset.overallExchangeRate = uint256(1e18);
        poolAsset.depositsSuppliedInterestRateFactor = depositsSuppliedInterestRateFactor;
        poolAsset.depositsSuppliedInterestRate = routerInterestRate.wadMul(depositsSuppliedInterestRateFactor);
        /* poolAsset.savingsLiquidityBufferFactor = uint256(50000000000000000); // 10% */
        poolAsset.isStable = true;
        poolAsset.isRoutable = isRoutable;

        // debt asset

        poolAsset.exchangeRateData = exchangeRateData; //address to router to send collateral to anchor
        poolAsset.routerExchangeRate = routerExchangeRate; // storeed byways of anchor exchangeRateFeeder
        poolAsset.routerInterestRate = routerInterestRate; // eestimated by exchangeRateFeeder

        // remove revert on 0 rate factor
        // for yield assets that will mainly be used for converting from savings to collateral
        // we don't need to ever use the router
        if (isRoutable) {
            // anchor currently requirs 10 eth minimum on aust and ust
            poolAsset.routerMinSupplyRedeemAmount = (routerMinSupplyRedeemAmount*(10**poolAsset.decimals)).wadDiv(poolAsset.depositsSuppliedInterestRate.wadDiv(routerInterestRate)).wadMul(routerExchangeRate);

        }

        poolAsset.lastUpdatedTimestamp = block.timestamp;

        poolAsset.on = true;
    }

    function initDebtToken(
        PoolStorage.PoolAsset storage poolAsset,
        address debtWrappedAsset,
        uint256 debtInterestRateFactor,
        uint256 ltv
    ) internal {
        (
          ,
          uint256 routerInterestRate
        ) = _getInterestData(poolAsset.exchangeRateData);

        uint256 borrowInterestRate = routerInterestRate.wadMul(debtInterestRateFactor);
        poolAsset.isDebt = true;
        poolAsset.borrowInterestRate = borrowInterestRate;
        poolAsset.debtWrappedAsset = debtWrappedAsset; // wrapped asset representing
        poolAsset.debtInterestRateFactor = debtInterestRateFactor; // percentage of interest rate of collateral rate to be the borrow rate --- 20% (borrow rate) * 50% = 10%
        // poolAsset.borrowInterestRate = routerInterestRate.wadMul(debtInterestRateFactor);
        poolAsset.borrowExchangeRate = uint256(1e18);

        /* poolAsset.minDebtTimeframe = uint256(5259486); // 2 months */
        /* poolAsset.maxDebtTimeframe = uint256(7257600); // 3 months */
        /* poolAsset.fullLiquidationTimeframe = uint256(14515200); // 4 months */

        poolAsset.ltv = ltv;
        /* poolAsset.maxAmortizationTime = 7257600; // 3 months */
        poolAsset.liquidationThreshold = uint256(1e18);
        poolAsset.minRepayFactor = uint256(600000000000000000);
        poolAsset.maxRepayFactor = uint256(900000000000000000);

        poolAsset.minDebtThresholdValue = (2000**poolAsset.decimals); // deebt threshold for 100% liquidation
        poolAsset.maxDebtLiquidationFactor = uint256(200000000000000000); // 20% of principal is max liquidator can remove


    }

    /**
     * @dev Gets exchange rate and interest rate from the routers exchange rate data contract
     **/
    function _getInterestData(address _exchangeRateData) public view returns (uint256, uint256) {
        (
            uint256 interestRate,
            uint256 exchangeRate
        ) = IExchangeRateData(_exchangeRateData).getInterestData();
        return (exchangeRate, interestRate);
    }

    /**
     * @dev Accrue exchange rates and update state based on router
     **/
    function accrueInterest(
        PoolStorage.PoolAsset storage poolAsset
    ) internal {
        (
            uint256 routerExchangeRate,
            uint256 routerInterestRate
        ) = _getInterestData(poolAsset.exchangeRateData);

        if (poolAsset.routerExchangeRate >= routerExchangeRate) {
            poolAsset.lastUpdatedTimestamp = block.timestamp;
            return;
        }

        uint256 routerExchangeRateAccrued = routerExchangeRate.sub(poolAsset.routerExchangeRate);
        // rate at which ER accrued since last update
        uint256 rateAccrued = routerExchangeRateAccrued.wadDiv(poolAsset.routerExchangeRate);

        if (poolAsset.isCollateral) {
            accrueCollateral(
                poolAsset,
                rateAccrued
            );
        }
        // console.log("in after accrueCollateral");

        if (poolAsset.wrapped != address(0)) {
        /* if (poolAsset.isSavings) { */
            // console.log("in after isSavings");

            uint256 debtScaledSupply = 0;
            if (poolAsset.debtWrappedAsset != address(0)) {
                // update debt | borrow
                uint256 debtScaledSupply = IDebtToken(poolAsset.debtWrappedAsset).totalScaledSupply();
                // console.log("in after debtScaledSupply", debtScaledSupply);
            }

            // lended to borrowers
            uint256 lendableAccrued;
            // get b4 update
            uint256 lastUpdatedLendableTotalSupply = poolAsset.totalDepositsLendable;

            // collateralRouterMinSupplyRedeemAmountd supply

            if (debtScaledSupply != 0) {
                uint256 lastUpdatedDebtTotalSupply = debtScaledSupply.wadMul(poolAsset.borrowExchangeRate);
                poolAsset.borrowInterestRate = routerInterestRate.wadMul(poolAsset.debtInterestRateFactor);
                (
                    uint256 borrowExchangeRate
                ) = accrueDebt(
                    poolAsset,
                    rateAccrued
                );
                uint256 updatedDebtTotalSupply = debtScaledSupply.wadMul(poolAsset.borrowExchangeRate);
                uint256 debtAccrued = updatedDebtTotalSupply.sub(lastUpdatedDebtTotalSupply);
                // deposits
                // can lendable supply just use the borrow index?
                // it can't because bridging may fail and need to rebalance
                // lended out to borrowers
                // update lending amounts
                // lending is done by principal andd not index
                (
                    uint256 updatedLendableTotalSupply
                ) = accrueLendableSupply(
                    poolAsset,
                    debtAccrued
                );
                lendableAccrued = updatedLendableTotalSupply.sub(poolAsset.totalDepositsLendable);

            }

            // get collateralRouterMinSupplyRedeemAmountd assets
            uint256 routerSuppliedTotalScaledSupply = IAvaToken(poolAsset.wrapped).routerSuppliedTotalScaledSupply();
            uint256 lastUpdateDepositsSuppliedTotalScaledSupply = routerSuppliedTotalScaledSupply.wadMul(poolAsset.depositsSuppliedExchangeRate);
            // console.log("in after accrue routerSuppliedTotalScaledSupply", routerSuppliedTotalScaledSupply);
            poolAsset.depositsSuppliedInterestRate = routerInterestRate.wadMul(poolAsset.depositsSuppliedInterestRateFactor);

            // accrue the router supplied assets
            (
                uint256 depositsSuppliedExchangeRate
            ) = accrueDepositsSupplied(
                poolAsset,
                rateAccrued
            );

            uint256 updatedRouterTotalSupply = routerSuppliedTotalScaledSupply.wadMul(depositsSuppliedExchangeRate);
            uint256 collateralRouterMinSupplyRedeemAmountSupplyAccrued = updatedRouterTotalSupply.sub(lastUpdateDepositsSuppliedTotalScaledSupply);
            // console.log("in after accrue updatedRouterTotalSupply", updatedRouterTotalSupply);

            // est anchor exchange ratte

            // anchor
            // get last updated totalSupply of anchor asset Which is principal+interest
            // get updated totalSupply of anchor asset Which is principal+interest
            // update variable
            accrueOverallDepositExchangeRate(
                poolAsset,
                lendableAccrued.add(collateralRouterMinSupplyRedeemAmountSupplyAccrued), // aDAI appreciation | amount from anchor since last update
                lastUpdateDepositsSuppliedTotalScaledSupply.add(lastUpdatedLendableTotalSupply) // previous totalSupply overall
            );
        }

        // update
        poolAsset.lastUpdatedTimestamp = block.timestamp;
        poolAsset.routerExchangeRate = routerExchangeRate;
        poolAsset.routerInterestRate = routerInterestRate;
    }

    /**
     * @dev Accrue router supplied assets on deposits
     **/
    function accrueDepositsSupplied(
        PoolStorage.PoolAsset storage poolAsset,
        uint256 rateAccrued
    ) internal returns (uint256) {
        uint256 supplyRouterRateAccrued = rateAccrued.wadMul(poolAsset.depositsSuppliedInterestRateFactor); // accrud/last*depositsSuppliedInterestRateFactor
        poolAsset.depositsSuppliedExchangeRate = poolAsset.depositsSuppliedExchangeRate.add(poolAsset.depositsSuppliedExchangeRate.wadMul(supplyRouterRateAccrued));
        return poolAsset.depositsSuppliedExchangeRate;
    }
    // =========================================================
    // collateral

    /**
     * @dev Accrue router supplied assets on collateral
     **/
    function accrueCollateral(
        PoolStorage.PoolAsset storage collateralAsset,
        uint256 rateAccrued
    ) internal {
        // complete amount to mint to reserve
        uint256 collateralTotalScaledSupply = ICollateralToken(collateralAsset.collateralAssetWrapped).totalScaledSupply();
        uint256 previousCollateralTotalSupply = collateralTotalScaledSupply.wadMul(collateralAsset.collateralExchangeRate);

        // accrued to account for
        uint256 collateralPremium = rateAccrued.wadMul(collateralAsset.collateralInterestRateFactor);
        // get amount with exchange rate without factoring reserve factor

        // in order to accomplish reserver factor mint, we must get exchange rate without factoring the reserve factor
        // we then use that to result the simulated total supply
        // that amount is applied to reservee factor
        uint256 updatedCollateralTotalSupply = collateralTotalScaledSupply.wadMul(
                collateralAsset.collateralExchangeRate.add(collateralAsset.collateralExchangeRate.wadMul(collateralPremium)
            )
        );



        uint256 collateralAccruedRate = collateralPremium.wadMul(ONE_FACTOR.sub(collateralAsset.reserveFactor));
        collateralAsset.collateralExchangeRate = collateralAsset.collateralExchangeRate.add(collateralAsset.collateralExchangeRate.wadMul(collateralAccruedRate));

        /* uint256 collateralTotalSupplyAccrued = collateralTotalScaledSupply.wadMul(collateralAsset.collateralExchangeRate).sub(previousCollateralTotalSupply); */
        /* ICollateralToken(collateralAsset.collateralAssetWrapped).mintToReserve(collateralTotalSupplyAccrued.wadMul(collateralAsset.reserveFactor), collateralAsset.collateralExchangeRate); */

        ICollateralToken(collateralAsset.collateralAssetWrapped).mintToReserve((updatedCollateralTotalSupply.sub(previousCollateralTotalSupply)).wadMul(collateralAsset.reserveFactor), collateralAsset.collateralExchangeRate);
    }

    /**
     * @dev LendableSupply increases by lastLendableTotalSupply + debt accrued from accrueDebt function
     **/
    function accrueLendableSupply(
        PoolStorage.PoolAsset storage poolAsset,
        uint256 debtAccrued
    ) internal returns (uint256) {
        uint256 lastLendableTotalSupply = IAvaToken(poolAsset.wrapped).lendableTotalSupplyPrincipal(); // total amount loaned or free to lend
        uint256 totalDepositsLendable = lastLendableTotalSupply.add(debtAccrued); // last updatedd lend + borrower repayments (and suedo repayments)
        poolAsset.totalDepositsLendable = totalDepositsLendable;
        return totalDepositsLendable;
    }

    /**
     * @dev Accrue debt exchange rates
     **/
    function accrueDebt(
        PoolStorage.PoolAsset storage poolAsset,
        uint256 routerExchangeRateAccrued
    ) internal returns (uint256) {
        uint256 lastBorrowExchangeRate = poolAsset.borrowExchangeRate;
        uint256 rateAccrued = routerExchangeRateAccrued.wadMul(poolAsset.debtInterestRateFactor); // accrud/last*debtInterestRateFactor
        poolAsset.borrowExchangeRate = lastBorrowExchangeRate.add(lastBorrowExchangeRate.wadMul(rateAccrued));
        return poolAsset.borrowExchangeRate;
    }

    /**
     * @dev Accrue savings exchange rate from debt accrued and router accrued combined
     **/
    function accrueOverallDepositExchangeRate(
        PoolStorage.PoolAsset storage poolAsset,
        uint256 totalRepay, // amount paid debt plus appreciation since last update
        uint256 previousTotalSupply
    ) internal {
        if (totalRepay <= 0) {
            return;
        }
        // console.log("after totalRepay");

        uint256 lastUpdatedOverallDepositIndex = poolAsset.overallExchangeRate;

        // 89.91008991008991008991008991009 = 90 / 1.001
        // 90 = 89.91008991008991008991008991009 * 1.001
        // repay = 10
        // 1.1011 = 1.001 + (1.001 * ((10*(1-.1)) / 90) )
        // 99 = 1.1011 * 89.91008991008991008991008991009
        poolAsset.overallExchangeRate = lastUpdatedOverallDepositIndex.add((lastUpdatedOverallDepositIndex.wadMul((totalRepay.wadMul(ONE_FACTOR.sub(poolAsset.reserveFactor))).wadDiv(previousTotalSupply))));
        // send 10% to reserves
        // console.log("after overallExchangeRate");

        // 1 = 10 * .1
        IAvaToken(poolAsset.wrapped).mintToSharedTreasury(totalRepay.wadMul(poolAsset.reserveFactor), poolAsset.overallExchangeRate);
    }

    /**
     * @dev Simulate borrow exchange rate on view calls
     **/
    function simulateBorrowExchangeRate(
        uint256 routerExchangeRate, // latest updated
        uint256 lastUpdatedRouterExchangeRate,
        uint256 debtInterestRateFactor,
        uint256 lastUpdatedBorrowExchangeRate
    ) external view returns (uint256) {
        if (lastUpdatedRouterExchangeRate >= routerExchangeRate) { return lastUpdatedBorrowExchangeRate; }
        // amount accrued since last update
        uint256 routerExchangeRateAccrued = routerExchangeRate.sub(lastUpdatedRouterExchangeRate);
        uint256 rateAccrued = (routerExchangeRateAccrued.wadDiv(lastUpdatedRouterExchangeRate)).wadMul(debtInterestRateFactor); // accrud/last*debtInterestRateFactor
        return lastUpdatedBorrowExchangeRate.add(lastUpdatedBorrowExchangeRate.wadMul(rateAccrued));
    }

    struct simulateOverallExchangeRateParams {
        uint256 overallExchangeRate;
        uint256 totalDepositsLendable;
        uint256 debtScaledSupply;
        uint256 lastUpdatedDepositRouterTotalSupply;
        address wrapped;
        address debtWrappedAsset;
    }

    /**
     * @dev Simulate overall exchange rate on view calls
     * Return the exchange rate to simulate how much a users balance is in underlying asset
     **/
    function simulateOverallExchangeRate(
        uint256 overallExchangeRate, // poolAsset.overallExchangeRate
        uint256 routerExchangeRate,
        uint256 lastUpdatedRouterExchangeRate, // poolAsset.routerExchangeRate,
        bool isSavings, //poolAsset.isSavings,
        address debtWrappedAsset,// poolAsset.debtWrappedAsset,
        uint256 totalDepositsLendable, // poolAsset.totalDepositsLendable,
        uint256 lastUpdatedBorrowExchangeRate, // poolAsset.borrowExchangeRate,
        uint256 updatedBorrowExchangeRate,
        uint256 lastUpdatedDepositSuppliedExchangeRate,
        uint256 updatedDepositsSuppliedExchangRate,
        address wrapped, // poolAsset.wrapped
        uint256 reserveFactor // poolAsset.reserveFactor
    ) external view returns (uint256) {
        simulateOverallExchangeRateParams memory params;
        params.overallExchangeRate = overallExchangeRate;
        params.totalDepositsLendable = totalDepositsLendable;
        params.wrapped = wrapped;
        params.debtWrappedAsset = debtWrappedAsset;

        if (!isSavings) {
            return 0;
        }

        if (lastUpdatedRouterExchangeRate >= routerExchangeRate) {
            return params.overallExchangeRate;
        }


        params.debtScaledSupply = 0;
        // if asset being simulated is a debt asset
        if (params.debtWrappedAsset != address(0)) {
            // update debt | borrow
            params.debtScaledSupply = IDebtToken(params.debtWrappedAsset).totalScaledSupply();
        }

        uint256 lendableAccrued;
        // simulate accrued debt
        if (params.debtScaledSupply != 0) {
            uint256 lastUpdatedDebtTotalSupply = params.debtScaledSupply.wadMul(lastUpdatedBorrowExchangeRate);
            uint256 lendableAccrued = params.debtScaledSupply.wadMul(updatedBorrowExchangeRate).sub(lastUpdatedDebtTotalSupply);
        }
        // get collateralRouterMinSupplyRedeemAmount assets
        params.lastUpdatedDepositRouterTotalSupply = IAvaToken(params.wrapped).routerSuppliedTotalScaledSupply().wadMul(lastUpdatedDepositSuppliedExchangeRate);

        uint256 depositRouterAccrued = IAvaToken(params.wrapped).routerSuppliedTotalScaledSupply().wadMul(updatedDepositsSuppliedExchangRate).sub(params.lastUpdatedDepositRouterTotalSupply);

        return accrueOverallDepositExchangeRateSimulated(
            params.overallExchangeRate,
            lendableAccrued.add(depositRouterAccrued), // aDAI appreciation | amount from anchor since last update
            params.lastUpdatedDepositRouterTotalSupply.add(params.totalDepositsLendable), // previous totalSupply overall
            reserveFactor
        );
    }

    /**
     * @dev Simulate overall exchange rate formula
     **/
    function accrueOverallDepositExchangeRateSimulated(
        uint256 overallExchangeRate,
        uint256 totalRepay,
        uint256 previousTotalSupply,
        uint256 reserveFactor
    ) internal view returns (uint256) {
        if (totalRepay <= 0) {
            return overallExchangeRate;
        }
        return overallExchangeRate.add((overallExchangeRate.wadMul((totalRepay.wadMul(ONE_FACTOR.sub(reserveFactor))).wadDiv(previousTotalSupply))));
    }

    /**
     * @dev Simulate collateral exchange rate formula
     **/
    function simulateCollateralExchangeRate(
        uint256 routerExchangeRate,
        uint256 lastUpdatedRouterExchangeRate,
        uint256 lastUpdatedCollateralExchangeRate,
        uint256 collateralInterestRateFactor,
        uint256 reserveFactor
    ) external view returns (uint256) {
        if (lastUpdatedRouterExchangeRate >= routerExchangeRate) { return lastUpdatedCollateralExchangeRate; }
        uint256 routerExchangeRateAccrued = (routerExchangeRate.sub(lastUpdatedRouterExchangeRate)).wadDiv(lastUpdatedRouterExchangeRate);
        uint256 rateAccrued = routerExchangeRateAccrued.wadMul(collateralInterestRateFactor).wadMul(ONE_FACTOR.sub(reserveFactor)); // accrud/last*debtInterestRateFactor
        uint256 updatedCollateralExchangeRate = lastUpdatedCollateralExchangeRate.add(lastUpdatedCollateralExchangeRate.wadMul(rateAccrued));
        return updatedCollateralExchangeRate;
    }

    /**
     * @dev Simulate lendable exchange rate formula
     **/
    function simulateLendableTotalSupply(
        address debtWrappedAsset,
        uint256 updatedBorrowExchangeRate,
        uint256 totalDepositsLendable,
        uint256 routerExchangeRate,
        uint256 lastUpdatedRouterExchangeRate,
        uint256 lastUpdatedBorrowExchangeRate
    ) external view returns (uint256) {
        if (routerExchangeRate <= lastUpdatedRouterExchangeRate) { return totalDepositsLendable; }
        uint256 debtTotalScaledSupply = IDebtToken(debtWrappedAsset).totalScaledSupply();
        uint256 lastUpdatedDebtTotalSupply = debtTotalScaledSupply.wadMul(lastUpdatedBorrowExchangeRate);
        uint256 debtTotalSupply = debtTotalScaledSupply.wadMul(updatedBorrowExchangeRate);
        uint256 debtTotalSupplyAccrued = debtTotalSupply.sub(lastUpdatedDebtTotalSupply);
        return totalDepositsLendable.add(debtTotalSupplyAccrued);
    }

    /**
     * @dev Simulate router deposits exchange rate formula
     **/
    function simulateDepositsSuppliedExchangeRate(
        uint256 routerExchangeRate,
        uint256 lastUpdatedRouterExchangeRate,
        uint256 lastUpdatedDepositsExchangeRate,
        uint256 depositsSuppliedInterestRateFactor
    ) internal view returns (uint256) {
        if (routerExchangeRate <= lastUpdatedRouterExchangeRate) { return lastUpdatedDepositsExchangeRate; }
        uint256 routerExchangeRateAccrued = routerExchangeRate.sub(lastUpdatedRouterExchangeRate);
        uint256 rateAccrued = routerExchangeRateAccrued.wadDiv(lastUpdatedRouterExchangeRate); // accrud/last*debtInterestRateFactor
        uint256 lastDepositsSuppliedExchangRate = lastUpdatedDepositsExchangeRate;
        uint256 depositsSuppliedRateAccrued = rateAccrued.wadMul(depositsSuppliedInterestRateFactor);
        return lastDepositsSuppliedExchangRate.add(lastDepositsSuppliedExchangRate.wadMul(depositsSuppliedRateAccrued));
    }

    /**
     * @dev Gets last updated savings interest rate 
     * This follows simulations
     **/
    function getAssetSavingsInterestRate(
        address wrapped,
        uint256 borrowInterestRate,
        uint256 savingsRouterRate,
        uint256 totalDebt,
        uint256 lendTotalSupply,
        uint256 savingsRouterTotalSupply
    ) internal view returns (uint256) {
        uint256 lendInterestReturn;
        if (totalDebt != 0) {
            lendInterestReturn = totalDebt.wadMul(borrowInterestRate);
        }
        uint256 totalSupplySimulated = lendTotalSupply.add(savingsRouterTotalSupply);
        uint256 savingsRouterInterestReturn = savingsRouterTotalSupply.wadMul(savingsRouterRate);
        uint256 totalInterestReturn = lendInterestReturn.add(savingsRouterInterestReturn);
        if (totalInterestReturn == 0 || totalSupplySimulated == 0) { return 0; }
        return totalInterestReturn.wadDiv(totalSupplySimulated);
    }

    function validateLiquidationCall(
        PoolStorage.PoolAsset storage collateralAsset,
        PoolStorage.PoolAsset storage debtAsset,
        address borrower
    ) internal view {
        require(collateralAsset.on && debtAsset.on, "Error: One or both assets paused.");
        uint256 borrowerDebt = IERC20(debtAsset.debtWrappedAsset).balanceOf(borrower);
        require(borrowerDebt != 0, "Error: Borrower has no debt.");
    }

    /* function validateBorrowAndGetData(
        PoolStorage.PoolAsset storage collateralAsset,
        PoolStorage.PoolAsset storage debtAsset,
        uint256 collateralValueAvailableInEth,
        address user,
        address priceOracle,
        uint256 debtAmount
    ) internal view {
        require(collateralAsset.isCollateral && debtAsset.isSavings, "Error: Collateral is not collateral asset or Debt asset is not debt asset.");
        // collateralRouterMinSupplyRedeemAmount will revert if not enough
        uint256 availableAmount = IERC20(debtAsset.asset).balanceOf(debtAsset.wrapped);
        require(availableAmount >= debtAmount, "Error: Not enough liquidity.");

        uint256 availableAmountValueInEth = getValueInEth(
            debtAsset.asset,
            debtAsset.decimals,
            debtAmount,
            priceOracle
        );

        require(collateralValueAvailableInEth >= availableAmountValueInEth, "Error: Not enough collateral value available.");
    } */


    function validateDepositCollateralAndBorrow(
        PoolStorage.PoolAsset storage collateralAsset,
        PoolStorage.PoolAsset storage debtAsset,
        address user,
        uint256 borrowAmount,
        bool useSavings
    ) internal {
        require(collateralAsset.isCollateral && debtAsset.isSavings, "Error: Collateral is not collateral asset or Debt asset is not debt asset.");
        require(
          collateralAsset.isSavings && useSavings ||
          collateralAsset.isSavings && !useSavings,
          "Error: Collateral is not collateral asset or debt asset is not debt asset."
        );

        // enough to take out on debt
        // debt ltv/ctd is fixed upon position taking 
        // user cannot take less than the borrowAmount
        // aftr this validation function, user may receive less due to slippage and routing
        uint256 availableDebtBalance = IERC20(debtAsset.asset).balanceOf(debtAsset.wrapped);
        // console.log("availableDebtBalance", availableDebtBalance);
        require(availableDebtBalance >= borrowAmount, "Error: Available debt balance too low");

        // enough user deposited savings on asset
        // if using their avasToken to fund their collateral
        if (useSavings) {
            uint256 availableSavingsBalance = IERC20(collateralAsset.wrapped).balanceOf(user);
            require(availableDebtBalance >= borrowAmount, "Error: Available savings balance too low");
            // if savings asset being used is also a debt asset
            // allowing this would open up the ability to lower the interest rate
            // on savings assets
            // useSavings is mainly for yield underlying tokens like AUST and collateral parking tokens
            // like UST (avasUSTSavings) that are not ever loaned out
            // this way utilization of debt ratio cannot be impacted on interest
            require(!collateralAsset.isDebt, "Error: The savings asset cannot be a debt asset if using savings to initiate a borrow");
        }
    }

    function validateDepositSavings(
        PoolStorage.PoolAsset storage poolAsset
    ) internal view {
        require(poolAsset.isSavings && poolAsset.on, "Error: Not savings asset.");

        // collateralRouterMinSupplyRedeemAmount will revert is amount too low
        /* require(poolAsset.on, "Error: This asset is currently off."); */
    }

    /* function confirmCollateralWithdrawAmount(
        PoolStorage.Position storage position,
        PoolStorage.PoolAsset storage collateralAsset,
        uint256 amount,
        uint256 averageLtvThreshold,
        address priceOracle
    ) internal view returns (uint256) {
        uint256 collateral = ICollateralToken(collateralAsset.collateralAssetWrapped).balanceOfAndPrincipal(msg.sender);
        // console.log("confirmCollateralWithdrawAmount collateral", collateral);

        uint256 collateralValue = getValueInEth(
            collateralAsset.asset,
            collateralAsset.decimals,
            collateral,
            priceOracle
        );

        collateralValue = collateralValue.mul(10**collateralAsset.decimals).div(10**18);


        // console.log("confirmCollateralWithdrawAmount averageLtvThreshold2", averageLtvThreshold);

        require(averageLtvThreshold < collateralValue, "Error: Max LTV threshold");


        uint256 maxWithdrawValue = collateralValue.sub(averageLtvThreshold).mul(10**18).div(10**collateralAsset.decimals);
        // console.log("confirmCollateralWithdrawAmount maxWithdrawValue", maxWithdrawValue);

        uint256 maxWithdraw = getAmountFromValueInEth(
            collateralAsset.asset,
            collateralAsset.decimals,
            maxWithdrawValue,
            priceOracle
        );
        // console.log("confirmCollateralWithdrawAmount maxWithdraw", maxWithdraw);

        if (amount > maxWithdraw) {
            amount = maxWithdraw;
        }

        return amount;
    } */

    /* function updatePositionState(
        PoolStorage.Position storage position,
        PoolStorage.PoolAsset storage collateralAsset,
        PoolStorage.Position storage position,
        uint256 repayAmount,
        uint256 borrowAmount
    ) internal view returns (uint256) {
        uint256 debt = IERC20(debtAsset.debtWrappedAsset).balanceOf(msg.sender);
        if (debt == 0) {
          position.startTimestamp = block.timestamp;
        }

    } */

    /**
     * @dev Update user borrower state
     * Mainly used against liquidations for max timeframes
     **/
    function updateUserState(
        PoolStorage.UserData storage userData,
        PoolStorage.PoolAsset storage collateralAsset,
        PoolStorage.PoolAsset storage debtAsset,
        address account,
        uint256 amountAdded, // take
        uint256 amountRemoved, // repay
        bool totalRepay,
        bool liquidation
    ) internal {

        // debt asset
        if (amountAdded > 0) {
            // updateUserData called before burning/minting debt
            uint256 debtBalance = IERC20(debtAsset.debtWrappedAsset).balanceOf(account);
            // if new position on debt asset
            if (debtBalance == 0) {
                userData.borrowStartTimestamp = block.timestamp;
            }

            // if new position or removing total debt
            if (debtBalance <= amountRemoved) {
                userData.isBorrowing = false;
                userData.borrowStartTimestamp = 0;
            } else {
                userData.isBorrowing = true;
            }

        }

        // debt asset
        // update last repay for collateral to savings cooldown period before
        // borrower can withdraw
        // this prevents abuse from borrowing loop strats
        if (amountRemoved > 0) {
            userData.repayCount += 1;
            userData.lastRepayTimestamp = block.timestamp;
        }

        // if removing total debt
        // reset repayCount to 0
        // update isBorrowing to false
        // reset borrow start timestamp
        if (totalRepay) {
            userData.repayCount = 0;
            userData.isBorrowing = false;
            userData.borrowStartTimestamp = 0;
        }   


    }

    /**
     * @dev Check how much debt user has and adjust repay amount if needed
     **/
    function confirmRepayAmount(
        PoolStorage.PoolAsset storage debtAsset,
        uint256 amount
    ) internal view returns (uint256, uint256) {
        uint256 debt = IERC20(debtAsset.debtWrappedAsset).balanceOf(msg.sender);
        uint256 repayAmount = amount;
        // if amount sent > asset debt owed, update to owed
        if (amount > debt) {
            repayAmount = debt;
        }

        return (debt, repayAmount);
    }

    /**
     * @dev Confirm user has enough collateral to burn or update amount
     * Checks if amount is > than balance 
     * If debt is bad and amount is > use balance
     **/
    function confirmWithdrawCollateralAmount(
        address collateralAssetWrapped,
        uint256 collateralAmountToRemove
    ) internal view returns (uint256) {
        uint256 collateral = IERC20(collateralAssetWrapped).balanceOf(msg.sender);
        uint256 collateralWithdrawAmount = collateralAmountToRemove;
        // if amount sent > asset debt owed, update to owed
        if (collateralWithdrawAmount > collateral) {
            collateralWithdrawAmount = collateral;
        }

        return collateralWithdrawAmount;
    }

    function confirmSelfLiquidationCollateralAmount(
        address collateralAssetWrapped,
        uint256 collateralAmount,
        uint256 selfLiquidationPremium
    ) internal view returns (uint256) {
        uint256 collateral = IERC20(collateralAssetWrapped).balanceOf(msg.sender);
        uint256 collateralWithdrawAmount = collateralAmount;
        // if amount sent > asset debt owed, update to owed
        if (collateralWithdrawAmount > collateral) {
            collateralWithdrawAmount = collateral;
        }

        return collateralWithdrawAmount;
    }

    /* function validateRepay(
        PoolStorage.PoolAsset storage debtAsset,
        uint256 repayAmount,
        uint256 debt
    ) internal view {

        require(repayAmount != 0 && debt != 0, "Error: Repay and debt must be zero.");


        require(
          debtAsset.on &&
          debtAsset.isSavings,
          "Error: Pool currently not active."
        );
    } */

    function validateRepayAndWithdraw(
        PoolStorage.UserData storage userData,
        PoolStorage.PoolAsset storage debtAsset,
        PoolStorage.PoolAsset storage collateralAsset,
        uint256 repayAmount,
        uint256 debt,
        uint256 collateralWithdrawAmount
    ) internal view {

        if (userData.repayCount == 0) {
            // first repay must be greater than min repay factor and less than max repay amount
            // example must pay debt between 60%-90% of debt amount on the chosen debt asset
            // this increases the CTD ratio thus increasing liquidation risk
            // prevents loop strat abuse by requiring user to pay either majority or greater of their debt
            uint256 minRepayAmount = debt.wadMul(debtAsset.minRepayFactor);
            require(minRepayAmount < repayAmount, "Error: Repay amount must be greater than minimum repay factor amount.");

            uint256 maxRepayAmount = debt.wadMul(debtAsset.maxRepayFactor);
            require(maxRepayAmount > repayAmount, "Error: Repay amount must be less than maximum repay factor amount.");
        }


        if (debt != 0) {
            require(repayAmount > 0 && debt > 0, "Error: Repay is zero or debt is zero.");
        } else {
            // if user fully liquidated, repay in should be 0
            require(repayAmount == 0 && debt == 0, "Error: Repay and debt must be zero.");
        }
        require(
          collateralAsset.on &&
          debtAsset.on &&
          debtAsset.isSavings &&
          collateralAsset.isCollateral,
          "Error: Pool currently not active."
        );
        uint256 collateralAfter = IERC20(collateralAsset.collateralAssetWrapped).balanceOf(msg.sender).sub(collateralWithdrawAmount);
        // ensure the repayAmount isn't going to put users balance under the min redeem amount from router after
        // some protocols may have min/max deposit/withdraw amounts
        if (collateralAfter != 0) {
            require(collateralAfter.wadDiv(collateralAsset.routerExchangeRate) > collateralAsset.collateralRouterMinSupplyRedeemAmount, "Error: Remaining collateral balance after is too low.");
        }

    }

    function validateSelfLiquidation(
        PoolStorage.PoolAsset storage debtAsset,
        PoolStorage.PoolAsset storage collateralAsset,
        uint256 repayAmount,
        uint256 debt,
        uint256 collateralLiquidationAmount
    ) internal view {
        require(repayAmount > 0 && debt > 0, "Error: Repay is zero or debt is zero.");

        require(
          collateralAsset.on &&
          debtAsset.on &&
          debtAsset.isSavings &&
          collateralAsset.isCollateral,
          "Error: Pool currently not active."
        );
        uint256 balance = IERC20(collateralAsset.collateralAssetWrapped).balanceOf(msg.sender);
        require(balance >= collateralLiquidationAmount, "Error: Collateral balance is less than debt.");
        uint256 collateralAfter = balance.sub(collateralLiquidationAmount);
        if (collateralAfter != 0) {
            require(collateralAfter.wadDiv(collateralAsset.routerExchangeRate) > collateralAsset.collateralRouterMinSupplyRedeemAmount, "Error: Remaining collateral balance after is too low.");
        }
    }

    function validateWithdrawSavings(
        PoolStorage.PoolAsset storage poolAsset,
        PoolStorage.UserData storage userData,
        address account,
        uint256 amount,
        uint256 redeemToAccountAmount
    ) internal view {
        // require repay was in a previous block
        // prevents smart contract functions from looping repay/withdraw to prevent borrow loop strats
        require(block.timestamp.sub(userData.lastRepayTimestamp) > poolAsset.repayCooldownTime, "Error: Must wait more blocks to withdraw after repay or liquidation");
        // require(userData.lastRepayTimestamp < block.timestamp, "Error: Must wait more blocks to withdraw after repay or liquidation");
        // check aust balance if greater than simulated version
        uint256 avasRouterScaledSimulatedTotalSupply = IAvaToken(poolAsset.wrapped).routerSuppliedTotalScaledSupply();

        uint256 avasRouterBalance = IAvaToken(poolAsset.wrapped).routerSuppliedTotalSupply();

        require(avasRouterScaledSimulatedTotalSupply <= avasRouterBalance, "Error: Receipt asset not caught up yet, please wait a few blocks");

        uint256 userBalance = IERC20(poolAsset.wrapped).balanceOf(account);
        require(userBalance != 0, "Error: Balance is zero");

        require(amount.sub(redeemToAccountAmount) <= IERC20(poolAsset.asset).balanceOf(poolAsset.wrapped), "Error: Not enough liquidity, try lowering withdraw total.");
        require(poolAsset.isSavings && poolAsset.on, "Error: Pool currently not active.");

        uint256 userBalanceAfter = userBalance.sub(amount);


        if (userBalanceAfter != 0) {
            require(userBalanceAfter.wadDiv(poolAsset.routerExchangeRate) > poolAsset.routerMinSupplyRedeemAmount, "Error: Remaining balance after is too low.");
        }
    }

    function getUserTotalDebtInEth(
        mapping(address => PoolStorage.PoolAsset) storage poolAssets,
        mapping(uint256 => address) storage poolAssetsList,
        uint256 poolAssetsCount,
        address account,
        address priceOracle
    ) internal view returns (uint256) {
        uint256 totalDebt;
        for (uint256 i = 0; i < poolAssetsCount; i++) {
            address currentPoolAssetAddress = poolAssetsList[i];
            PoolStorage.PoolAsset storage currentPoolAsset = poolAssets[currentPoolAssetAddress];
            if (
              currentPoolAsset.debtWrappedAsset == address(0)
            ) {
                continue;
            }
            uint256 debt = IERC20(currentPoolAsset.debtWrappedAsset).balanceOf(account);
            totalDebt += debt.mul(10**18).div(10**currentPoolAsset.decimals);
        }
        return totalDebt;
    }

    /**
     * @dev Converts amount in eth to decimals requested
     **/
    function getAmountFromValueInEth(
        /* PoolStorage.PoolAsset storage poolAsset, */
        address asset,
        uint256 decimals,
        uint256 amount,
        address priceOracle
    ) internal view returns (uint256) {

        if (amount == 0) { return 0; }

        amount = amount.mul(10**decimals).div(10**18);

        uint256 price = uint256(IPriceConsumerV3(priceOracle).getLatestPrice(asset));

        uint8 priceDecimals = IPriceConsumerV3(priceOracle).decimals(asset);

        return amount.mul(uint256(price)).div(10**uint256(priceDecimals));
    }

    /**
     * @dev Converts amount into eth decimals
     **/
    function getValueInEth(
        address asset,
        uint256 decimals,
        uint256 amount,
        address priceOracle
    ) internal view returns (uint256) {
        if (amount == 0) { return 0; }
        uint256 price = uint256(IPriceConsumerV3(priceOracle).getLatestPrice(asset));
        uint8 priceDecimals = IPriceConsumerV3(priceOracle).decimals(asset);
        uint256 _ether = uint256(18);
        if (decimals != _ether) {
            if (decimals > _ether) {
                uint256 difference = decimals.sub(_ether);
                amount = amount.div(10**difference);
            } else {
                uint256 difference = _ether.sub(decimals);
                amount = amount.mul(10**difference);
            }
        }
        return amount.mul(uint256(price)).div(10**uint256(priceDecimals));
    }

    /* function updateCollateralIdle(
        address user,
        address collateralAsset,
        uint256 collateralAssetDecimals,
        address collateralAssetWrapped,
        uint256 collateralAssetsFactor,
        address debtAsset,
        uint256 debtAssetDecimals,
        uint256 repayAmount,
        address priceOracle
    ) internal {
        // console.log("updateCollateralIdle repayAmount", repayAmount);
        // console.log("updateCollateralIdle repayAmount.wadMul(collateralAssetsFactor)", repayAmount.wadMul(collateralAssetsFactor));

        uint256 repayValueInEth = getValueInEth(
            debtAsset,
            debtAssetDecimals,
            repayAmount.wadMul(collateralAssetsFactor),
            priceOracle
        );
        // console.log("updateCollateralIdle repayValueInEth", repayValueInEth);

        uint256 collateralAmountFromRepayInEth = getAmountFromValueInEth(
            collateralAsset,
            collateralAssetDecimals,
            repayValueInEth,
            priceOracle
        );
        // console.log("updateCollateralIdle collateralAmountFromRepayInEth", collateralAmountFromRepayInEth);

        ICollateralToken(collateralAssetWrapped).idleOnRepay(user, collateralAmountFromRepayInEth);
    } */

    function validateWithdrawCollateralAmount(
        uint256 totalCollateral,
        uint256 withdrawAmount
    ) internal view {
        require(withdrawAmount > uint256(10e18), "Error: Withdraw amount must be more than 10");
        require(totalCollateral.sub(withdrawAmount) > uint256(10e18), "Error: Resulting leftover amount must be more than 10");
    }


    /* function updateCollateralIdle(
        address user,
        address collateralAsset,
        uint256 collateralAssetDecimals,
        address collateralAssetWrapped,
        address debtAsset,
        uint256 debtAssetDecimals,
        uint256 repayAmount,
        address priceOracle
    ) internal {
        // console.log("updateCollateralIdle repayAmount", repayAmount);
        // console.log("updateCollateralIdle repayAmount.wadMul(collateralAssetsFactor)", repayAmount.wadMul(collateralAssetsFactor));

        uint256 repayValueInEth = getValueInEth(
            debtAsset,
            debtAssetDecimals,
            repayAmount,
            priceOracle
        );
        // console.log("updateCollateralIdle repayValueInEth", repayValueInEth);

        uint256 collateralAmountFromRepayInEth = getAmountFromValueInEth(
            collateralAsset,
            collateralAssetDecimals,
            repayValueInEth,
            priceOracle
        );
        // console.log("updateCollateralIdle collateralAmountFromRepayInEth", collateralAmountFromRepayInEth);

        ICollateralToken(collateralAssetWrapped).idleOnRepay(user, collateralAmountFromRepayInEth);
    } */


    /* function getCollateralValueAvailableInEth(
        mapping(address => PoolStorage.PoolAsset) storage poolAssets,
        mapping(uint256 => address) storage collateralAssetsList,
        uint256 collateralAssetsCount,
        address user,
        uint256 amount,
        address priceOracle
    ) internal view returns (uint256) {
        uint256 valueAvailableInEth;
        for (uint256 i = 0; i < collateralAssetsCount; i++) {
            address currentPoolAssetAddress = collateralAssetsList[i];
            PoolStorage.PoolAsset storage currentPoolAsset = poolAssets[currentPoolAssetAddress];
            if (!currentPoolAsset.isCollateral) {
                continue;
            }
            uint256 balanceAvailable = ICollateralToken(currentPoolAsset.collateralAssetWrapped).balanceOfAvailablePrincipal(user);
            valueAvailableInEth += getValueInEth(
                currentPoolAssetAddress,
                currentPoolAsset.decimals,
                balanceAvailable,
                priceOracle
            );
        }
        return valueAvailableInEth;
    } */


}
