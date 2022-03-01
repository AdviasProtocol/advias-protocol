//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;
import {IPoolAddressesProvider} from '../interfaces/IPoolAddressesProvider.sol';

/**
 * @title PoolStorage
 * @author Advias
 * @title Protocol storage
 */
contract PoolStorage {

    /**
     * @dev All parameters for each underlying asset money market
     *
     * Parameters:
     *
     * General
     * - `asset`
     * - `decimals` - Decimals of unerlying asset, all wrapped asset will match the underlying assets decimals
     * - `wrapped` - The savings avasToken for the pool asset
     * - `isCollateral`
     * - `isUST`
     * - `isSavings`
     * - `isDebt`
     * - `isStable`
     * - `on` - If asset can be used
     * - `router` - Router address responsible for Anchor or other integration
     * - `exchangeRateData` - Data responsible for returning integrated asset data
     * - `depositsSuppliedExchangeRate` - Exchange ra
     * - `depositsSuppliedInterestRateFactor`
     * - `depositsSuppliedInterestRate`
     * - `totalDepositsLendable`
     * * - the free-to-lend total plus accrued debt
     * * - manual tracking of assets designated to lending
     * * - tracked manually due to bridging interoperable delays
     * * - used mainly for knowing how much router owes incase bridging
     * * - any debt is calculated by actual balance of underlying asset
     * - `overallExchangeRate`
     * - `collateralAssetWrapped`
     * - `collateralInterestRateFactor`
     * - `collateralExchangeRate`
     * - `ctd`
     * - `debtWrappedAsset`
     * - `borrowExchangeRate`
     * - `borrowInterestRate`
     * - `maxDebtLiquidationFactor`
     * - `debtInterestRateFactor`
     * - `ltv`
     * - `maxCtdLiquidationThreshold`
     * - `liquidationThreshold`
     * - `minDebtThresholdValue`
     * - `liquidationBonusFactor`
     * - `collateralLiquidityBufferFactor`
     * - `savingsLiquidityBufferFactor`
     * - `routerExchangeRate` - Exchange rate of asset in Anchor or outside integration --- only used  to check how much accrued
     * - `routerInterestRate`- Interest rate of asset in Anchor or outside integration
     * - `routerMinSupplyRedeemAmount`
     * - `routerMaxSupplyRedeemAmount`
     * - `lastUpdatedTimestamp`
     * - `vault`
     * - `vaultFactor` - wad Percentage to go into vault (fee or usee as dividends)
     * - `reserve`
     * - `reserveFactor` - wad Percentage to go into insurance wallet
     * - `treasury`
     * - `treasuryFactor`
     **/

    struct PoolAsset {
        // - General
        address asset; // underlying
        uint256 decimals;
        address wrapped; // AvaToken savinsg
        bool isCollateral; // can be used as collateral
        bool isRoutable; // do we send this anywhere like anchor? assets like aust do not
        /* bool isUST; */
        bool isSavings;
        bool isDebt; // scalability
        bool isStable; // scalability
        bool on;
        uint256 lastUpdatedTimestamp;


        // - Savings
        uint256 depositsSuppliedExchangeRate; // router deposits
        uint256 depositsSuppliedInterestRateFactor; // percentage of interest rate to account for from router
        uint256 depositsSuppliedInterestRate;
        uint256 totalDepositsLendable; // tracked manually due to possible rebalance errors
        uint256 overallExchangeRate;
        uint256 maxRouterFactor; // max amount that can be routed as a percentage There must be x% 
        uint256 maxBorrowFactor; // max percentage of savings supply that be borrowed wad This keeps liquidity
        // - Collateral
        address collateralAssetWrapped;
        uint256 collateralInterestRateFactor; // amount of exchange rate to account for.  We need to cover fees
        uint256 collateralExchangeRate;
        uint256 collateralRouterMinSupplyRedeemAmount; // min amount router allows
        uint256 collateralLiquidityBufferFactor; // amount between contract aust amount and min needed amount, remaining goes to liquidity vault
        uint256 ctd;
        uint256 selfLiquidationPremium; // added premium as self percentage Used due to bridging fees to ensure full repay or more
        // - Debt and Borrowing
        address debtWrappedAsset;
        uint256 borrowExchangeRate;
        uint256 borrowInterestRate;
        uint256 debtInterestRateFactor; // routerInterestRate * debtInterestRateFactor = debtInterestRate (savings and debt rate)
        uint256 minDebtThresholdValue; // if debt below this amount then 100% of debt can be repaidd
        uint256 ltv; // 1e18
        uint256 maxDebtTimeframe; // max unix a position can be held for - such as a year
        uint256 savingsLiquidityBufferFactor; // amount between contract aust amount and min needed amount for liquidity, remaining goes to liquidity vault
        uint256 minRepayFactor;
        uint256 maxRepayFactor;
        uint256 repayCooldownTime; // unix how long between last repay and withdraw can user withdraw savings

        // - Integration
        address router; // protocol router contract for integration into protocols
        address exchangeRateData;
        uint256 routerExchangeRate; // storeed byways of anchor exchangeRateFeeder
        uint256 routerInterestRate; // estimated by exchangeRateFeeder
        uint256 routerMinSupplyRedeemAmount; // min amount router allows
        uint256 routerMaxSupplyRedeemAmount; // max amount router allows

        // - Liquidation
        uint256 maxDebtLiquidationFactor;
        uint256 maxCtdLiquidationThreshold; // 1e18
        uint256 liquidationThreshold; // 1e18
        uint256 liquidationBonusFactor; // % of collateral sent to liquidator

        // - Protocol vaults/reserves
        address vault;
        uint256 vaultFactor;
        address reserve;
        uint256 reserveFactor;
        address treasury;
        uint256 treasuryFactor;
    }

    struct UserData {
        uint256 borrowStartTimestamp;
        uint256 lastLiquidationTimestamp;
        uint256 lastRepayTimestamp;
        uint256 repayCount;
        bool isBorrowing; // if debt asset
    }

    // // usersData[account] => UserData
    // mapping(address => UserData) internal usersData;

    // usersData[account][underlyingDebt] => UserData
    mapping(address => mapping(address => UserData)) internal usersData;

    // poolAssetsList[underlying] => PoolAsset
    mapping(address => PoolAsset) internal poolAssets;

    // poolAssetsList[uint256] => mapping
    mapping(uint256 => address) public poolAssetsList;

    uint256 public poolAssetsCount;

    uint256 public collateralAssetsCount;

    uint256 public savingsAssetsCount;

    uint256 public debtAssetsCount;

    /**
     * @dev Time to give borrower after liquidations on ctd
     **/
    uint256 public ctdGraceTimeperiod;


    bool internal paused; // Overall protocol - Used for emergency only by admin only

    IPoolAddressesProvider internal addressesProvider;

    /* uint256 internal partialLiquidationFactor; // liquidation percentage of debt when using ltv ratio
    uint256 internal minPartialLiquidationValueInEth; // > partial, else 100% liquidation
    uint256 internal ctdLiquidationFactor; // liquidation percentage of debt when using ctd ratio */

}
