//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {General} from '../libraries/General.sol';
import {WadRayMath} from '../libraries/WadRayMath.sol';
import {IPoolAddressesProvider} from '../interfaces/IPoolAddressesProvider.sol';
import {PoolStorage} from './PoolStorage.sol';
import {IPool} from '../interfaces/IPool.sol';
import {PoolLogic} from '../libraries/PoolLogic.sol';
import {ICollateralToken} from '../interfaces/ICollateralToken.sol';
import {IAvaToken} from '../interfaces/IAvaToken.sol';
import {IDebtToken} from '../interfaces/IDebtToken.sol';
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRewardsTokenBase} from '../tokens/IRewardsTokenBase.sol';
import {ILiquidationCaller} from '../interfaces/ILiquidationCaller.sol';
import {IRouter} from '../interfaces/IRouter.sol';
import "hardhat/console.sol";

/**
 * @title Pool
 * @author Advias
 * @title Protocols main interaction functions
 */
/* contract Pool is Initializable, UUPSUpgradeable, OwnableUpgradeable, IPool, PoolStorage { */
contract Pool0 is IPool, PoolStorage {

    using SafeMath for uint256;
    /* using SafeERC20Upgradeable for IERC20Upgradeable; */
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;

    modifier whenNotPaused() {
        require(!paused, "Errors: Pool paused");
        _;
    }

    function getAddressesProvider() external view override returns (address) {
        // in storage
        return address(addressesProvider);
    }

    constructor(IPoolAddressesProvider provider) {
        addressesProvider = provider;
    }

    /* function initialize(IPoolAddressesProvider provider) external initializer {
        addressesProvider = provider;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {} */

    /**
     * @dev Deposits underlying assets in return for appreciating avaTokens
     * @param account Address to receive avaTokens
     * @param asset Underlying asset to transfer in
     * @param amount Amount of underlying asset to transfer in
     **/
    function depositSavings(
        address account,
        address asset, // savings asset
        uint256 amount
    ) external whenNotPaused override {
        PoolAsset storage poolAsset = poolAssets[asset];
        // update exchangeRate
        // get rate

        PoolLogic.accrueInterest(
            poolAsset
        );

        // dont check amount, router reverts is min not hit
        PoolLogic.validateDepositSavings(
            poolAsset
        );

        // send underlying deposited to wrapped token contract
        // transfer from msg.sender
        IERC20(asset).safeTransferFrom(msg.sender, poolAsset.wrapped, amount);

        // how much to send to anchor
        // accounts for bridging fees
        uint256 routerSupplyAmount = amount;
        console.log("depositSavings routerSupplyAmount 1", routerSupplyAmount);

        if (poolAsset.isDebt && poolAsset.isRoutable) {
            routerSupplyAmount = IRouter(poolAsset.router).getAllotAmountOnSupply(
                amount, // 100
                poolAsset.wrapped,
                poolAsset.borrowInterestRate,
                poolAsset.debtWrappedAsset,
                poolAsset.depositsSuppliedInterestRate,
                poolAsset.routerMinSupplyRedeemAmount,
                poolAsset.decimals
            );
            console.log("depositSavings routerSupplyAmount 2", routerSupplyAmount);
            (bool localVaultUsed, uint256 amountBack) = IRouter(asset).deposit(
                asset,
                amount,
                0,
                address(this)
            );
        }



        // mint token to account
        IAvaToken(poolAsset.wrapped).mint_(
            account,
            amount.sub(routerSupplyAmount),
            routerSupplyAmount,
            poolAsset.overallExchangeRate
        );

        emit DepositSavings(
            msg.sender,
            asset,
            amount
        );

    }

    /**
     * @dev Deposits underlying asset as collateral in return for underlying debt asset
     * Returns avaToken as collateral and avaToken as debt
     *
     * @param _collateralAsset Underlying asset to transfer in as collateral
     * @param _debtAsset Underlying asset to receive as debt
     * @param account Acccount to receive collateral and debt
     * @param amount Amount of underlying asset to transfer in
     * @param useSavings If collateral should be transfered in or use msg.sender savings
     *
     * useSavings This works if savings asset is also a collateral asset
     * The amount back as debt is amount*LTV or amount/CTD, whichever is least
     **/
    function depositCollateralAndBorrow(
        address _collateralAsset, //
        address _debtAsset, // wrapp to borrow
        address account, // on behalf of
        uint256 amount, // collateral amount ---> receive amount*ltv in debt
        bool useSavings
    ) external override whenNotPaused {
        PoolAsset storage collateralAsset = poolAssets[_collateralAsset];
        PoolAsset storage debtAsset = poolAssets[_debtAsset];

        PoolLogic.accrueInterest(
            collateralAsset
        );

        PoolLogic.accrueInterest(
            debtAsset
        );

        // ex: 100,000 = 100,000 * 1.000
        uint256 collateralValueInEth = PoolLogic.getValueInEth(
            _collateralAsset,
            collateralAsset.decimals,
            amount,
            addressesProvider.getPriceOracle()
        );

        // ex: 80,000 = 100,000 / 1.25
        uint256 maxBorrowValueInEthCtd = collateralValueInEth.wadDiv(collateralAsset.ctd);
        console.log("depositCollateralAndBorrow maxBorrowValueInEthCtd", maxBorrowValueInEthCtd);
        // ex: 100,000 = 100,000 * 1.0
        uint256 maxBorrowValueInEthLtv = collateralValueInEth.wadMul(debtAsset.ltv);
        console.log("depositCollateralAndBorrow maxBorrowValueInEthLtv", maxBorrowValueInEthLtv);
        // ex: 80,000
        uint256 maxBorrowValueInEth = maxBorrowValueInEthCtd < maxBorrowValueInEthLtv ? maxBorrowValueInEthCtd : maxBorrowValueInEthLtv;

        // ex: 80,080 = 80,000 * 1.001
        uint256 borrowAmount = PoolLogic.getAmountFromValueInEth(
            debtAsset.asset,
            debtAsset.decimals,
            maxBorrowValueInEth,
            addressesProvider.getPriceOracle()
        );

        PoolLogic.validateDepositCollateralAndBorrow(
            collateralAsset,
            debtAsset,
            msg.sender,
            borrowAmount,
            useSavings
        );

        /* IERC20(_collateralAsset).safeTransferFrom(msg.sender, collateralAsset.collateralAssetWrapped, amount); */

        if (!useSavings) {
            // send underlying in as collateral
            IERC20(_collateralAsset).safeTransferFrom(msg.sender, collateralAsset.collateralAssetWrapped, amount);
        } else {
            // use savings asset as collateral
            // savings assets that can be used as collateral are not debtable assets
            // therefor there is no interest rate abuse ability if a user `burnTo`s too much
            IAvaToken(debtAsset.wrapped).burnTo(msg.sender, amount, collateralAsset.collateralAssetWrapped, collateralAsset.overallExchangeRate);
        }

        ICollateralToken(collateralAsset.collateralAssetWrapped).mint(msg.sender, amount, collateralAsset.collateralExchangeRate, !useSavings);

        IDebtToken(debtAsset.debtWrappedAsset).mint(
            msg.sender,
            borrowAmount,
            debtAsset.borrowExchangeRate
        );

        // transfer underlying to borrower
        IAvaToken(debtAsset.wrapped).transferUnderlyingTo(msg.sender, borrowAmount);

        // collateral runs at a discount to the actual APY.
        // reason: interoperable calculation issues may occur
        // any excess appreciation is sent to our liquidity vault to be used for avaTokens
        ICollateralToken(collateralAsset.collateralAssetWrapped).supplyLiquidityVault(_debtAsset, addressesProvider.getLiquidityVault(), collateralAsset.collateralLiquidityBufferFactor);

        /* userData.isBorrowing = true; */
        updateIsBorrowing(msg.sender, _debtAsset, true);

        emit DepositCollateralAndBorrow(
            _collateralAsset,
            _debtAsset,
            msg.sender,
            amount,
            borrowAmount
        );

    }

    struct repayAndWithdrawParams {
        address _collateralAsset;
        address _debtAsset;

    }
    // repay debt and withdraw collateral
    // only full repay
    /**
     * @dev Deposits underlying asset to repay debt and withdraws collateral asset 1:1 ratio
     * @param _collateralAsset Underlying collateral asset to withdraw
     * @param _debtAsset Underlying debt asset to repay and transfer in
     * @param amount Amount of debt to repay and transfer in
     * @param sendToSavings If to send collateral to savings or withdraw
     *
     * useSavings This works if collateral asset is also a savings asset
     **/
    function repayAndWithdraw(
        address _collateralAsset,
        address _debtAsset,
        uint256 amount,
        bool sendToSavings
    ) external whenNotPaused override {
        repayAndWithdrawParams memory params;
        params._collateralAsset = _collateralAsset;
        params._debtAsset = _debtAsset;

        PoolAsset storage collateralAsset = poolAssets[params._collateralAsset];
        PoolAsset storage debtAsset = poolAssets[params._debtAsset];
        UserData storage userData = usersData[msg.sender][params._debtAsset];
        
        PoolLogic.accrueInterest(
            collateralAsset
        );

        PoolLogic.accrueInterest(
            debtAsset
        );

        // requirements
        // repay >= debt
        // update repay amount if >
        // get user debt amount
        // upates amortizationTimestamp if >

        (uint256 debt, uint256 repayAmount) = PoolLogic.confirmRepayAmount(
            debtAsset,
            amount
        );

        /* // requirements
        // min timeframe reached
        PoolLogic.validateRepayAndWithdraw(
            debtAsset,
            collateralAsset,
            repayAmount,
            debt
        ); */

        uint256 totalDebtInEth = PoolLogic.getUserTotalDebtInEth(
            poolAssets,
            poolAssetsList,
            poolAssetsCount,
            msg.sender,
            addressesProvider.getPriceOracle()
        );

        uint256 repayValueInEth = PoolLogic.getValueInEth(
            params._debtAsset,
            debtAsset.decimals,
            amount,
            addressesProvider.getPriceOracle()
        );

        // release 1:1
        uint256 collateralBurnAmount = PoolLogic.getAmountFromValueInEth(
            params._collateralAsset,
            collateralAsset.decimals,
            repayValueInEth,
            addressesProvider.getPriceOracle()
        );

        // confirm enough collateral
        // bad debt can cause less collateral or user can increase health by choosing specific collateral assets
        uint256 collateralWithdrawAmount = PoolLogic.confirmWithdrawCollateralAmount(
            collateralAsset.collateralAssetWrapped,
            collateralBurnAmount
        );

        // requirements
        // min timeframe reached
        PoolLogic.validateRepayAndWithdraw(
            userData,
            debtAsset,
            collateralAsset,
            repayAmount,
            debt,
            collateralWithdrawAmount
        );

        if (repayValueInEth >= totalDebtInEth) {
            // release all collateral when all debt is zero
            collateralWithdrawAmount = IERC20(collateralAsset.collateralAssetWrapped).balanceOf(msg.sender);
            /* userData.isBorrowing = false; */
            updateIsBorrowing(msg.sender, _debtAsset, false);
        }

        /* if (collateralAsset.isSavings && sendToSavings) {
            // send withdraw amount to the asset equivelent savings avaToken if exists
            ICollateralToken(collateralAsset.collateralAssetWrapped).burnToSavings(
                msg.sender,
                collateralWithdrawAmount,
                collateralAsset.wrapped,
                collateralAsset.collateralExchangeRate
            );
            IAvaToken(collateralAsset.wrapped).mint_(
                msg.sender,
                collateralWithdrawAmount,
                0,
                collateralAsset.overallExchangeRate
            );
            IAvaToken(collateralAsset.wrapped).supplyLiquidityVault(_debtAsset, addressesProvider.getLiquidityVault(), collateralAsset.savingsLiquidityBufferFactor);
        } else {
            ICollateralToken(collateralAsset.collateralAssetWrapped).burnAndRedeem(msg.sender, msg.sender, collateralWithdrawAmount, collateralAsset.collateralExchangeRate);
        } */

        // require to savings to avoid perpetual borrow to flashloan strategy
        // borrower can have collateral with no debt so no check
        ICollateralToken(collateralAsset.collateralAssetWrapped).burnToSavings(
            msg.sender,
            collateralWithdrawAmount,
            collateralAsset.wrapped,
            collateralAsset.collateralExchangeRate
        );
        IAvaToken(collateralAsset.wrapped).mint_(
            msg.sender,
            collateralWithdrawAmount,
            0,
            collateralAsset.overallExchangeRate
        );
        IAvaToken(collateralAsset.wrapped).supplyLiquidityVault(_debtAsset, addressesProvider.getLiquidityVault(), collateralAsset.savingsLiquidityBufferFactor);


        ICollateralToken(collateralAsset.wrapped).supplyLiquidityVault(_debtAsset, addressesProvider.getLiquidityVault(), collateralAsset.collateralLiquidityBufferFactor);


        // allows borrower to withdraw collateral on 0 debt balance
        // can happen on full liquidations
        if (repayAmount > 0) {
            IDebtToken(debtAsset.debtWrappedAsset).burn(msg.sender, repayAmount, debtAsset.borrowExchangeRate);
            // transfer in debt asset to repay
            IERC20(params._debtAsset).safeTransferFrom(msg.sender, debtAsset.wrapped, repayAmount);
        }

        updateLastRepayTimestamp(msg.sender, params._debtAsset, block.timestamp);

        // may not need here sine debt repay is accounted for
        emit RepayAndWithdraw(
            msg.sender,
            params._collateralAsset,
            params._debtAsset,
            repayAmount
        );

    }

    /**
     * @dev Withdraws underlying asset and burns avaToken savings
     * @param account Account to withdraw to
     * @param asset Underlying asset to withraw
     * @param amount Amount of savings to withdraw
     * @param emergency If to void any require statements
     **/
    function withdrawSavings(
        address account,
        address asset,
        uint256 amount,
        bool emergency
    ) external whenNotPaused override {
        PoolAsset storage poolAsset = poolAssets[asset];
        UserData storage userData = usersData[msg.sender][asset];

        PoolLogic.accrueInterest(
            poolAsset
        );

        // update amount if greater than user balance
        uint256 balance = IERC20(poolAsset.wrapped).balanceOf(account);
        console.log("withdrawSavings balance", balance);
        if (amount > balance) {
            amount = balance;
        }

        uint256 redeemToAccountAmount = amount;
        console.log("withdrawSavings redeemToAccountAmount 1", redeemToAccountAmount);
        // amount to withdraw from anchor and send directly to user
        // this is the difference between current amount in anchor minus amount required in anchor after withdraw
        // ex: UST is not used as debt and total supply is held in advias
        if (poolAsset.isDebt) {
            redeemToAccountAmount = IRouter(poolAsset.router).getAllotAmountOnRedeem(
                amount,  // amount account withdraw
                poolAsset.wrapped,
                poolAsset.borrowInterestRate,
                poolAsset.debtWrappedAsset,
                poolAsset.depositsSuppliedInterestRate,
                poolAsset.routerMinSupplyRedeemAmount,
                poolAsset.decimals
            );
            console.log("withdrawSavings redeemToAccountAmount 2", redeemToAccountAmount);
        }

        // ensure balance >= amount
        // ensure liquidity
        // ensure remaining balance > min balance
        PoolLogic.validateWithdrawSavings(
            poolAsset,
            userData,
            msg.sender,
            amount,
            redeemToAccountAmount
            /* emergency */
        );

        if (redeemToAccountAmount != 0) {
            // decimals update in redeem
            IAvaToken(poolAsset.wrapped).redeem(
                redeemToAccountAmount,
                msg.sender,
                emergency
            );
        }

        console.log("withdrawSavings after redeem");
        // redeemToAccountAmount doesn't inlude fees therefor can be reduced from totalDepositsLendable

        IAvaToken(poolAsset.wrapped).burn(
            msg.sender,
            amount,
            redeemToAccountAmount,
            poolAsset.overallExchangeRate
        );
        console.log("withdrawSavings after burn");

        emit WithdrawSavings(
            msg.sender,
            asset,
            amount
        );
    }

    function selfLiquidation(
        address _collateralAsset,
        address _debtAsset,
        uint256 amount
    ) external {
        PoolAsset storage collateralAsset = poolAssets[_collateralAsset];
        PoolAsset storage debtAsset = poolAssets[_debtAsset];

        PoolLogic.accrueInterest(
            collateralAsset
        );

        PoolLogic.accrueInterest(
            debtAsset
        );

        (uint256 debt, uint256 repayAmount) = PoolLogic.confirmRepayAmount(
            debtAsset,
            amount
        );

        uint256 totalDebtInEth = PoolLogic.getUserTotalDebtInEth(
            poolAssets,
            poolAssetsList,
            poolAssetsCount,
            msg.sender,
            addressesProvider.getPriceOracle()
        );

        uint256 repayValueInEth = PoolLogic.getValueInEth(
            _debtAsset,
            debtAsset.decimals,
            amount,
            addressesProvider.getPriceOracle()
        );

        // release 1:1
        repayValueInEth = repayValueInEth.add(repayValueInEth.wadMul(collateralAsset.selfLiquidationPremium));
        uint256 collateralLiquidationAmount = PoolLogic.getAmountFromValueInEth(
            _collateralAsset,
            collateralAsset.decimals,
            repayValueInEth,
            addressesProvider.getPriceOracle()
        );

        /* // confirm enough collateral
        // bad debt can cause less collateral or user can increase health by choosing specific collateral assets
        uint256 collateralLiquidationAmount = PoolLogic.confirmWithdrawCollateralAmount(
            collateralAsset.collateralAssetWrapped,
            collateralBurnAmount,
            collateralAsset.selfLiquidationPremium
        ); */

        // requirements
        // confirm collateral can cover required amount + premium
        // confirm after amount isn't under min balance
        PoolLogic.validateSelfLiquidation(
            debtAsset,
            collateralAsset,
            repayAmount,
            debt,
            collateralLiquidationAmount
        );

        // require to savings to avoid perpetual borrow to flashloan strategy
        ICollateralToken(collateralAsset.collateralAssetWrapped).burnAndRedeem(
            msg.sender,
            collateralAsset.wrapped,
            debtAsset.asset,
            collateralLiquidationAmount,
            collateralAsset.collateralExchangeRate
        );

        if (repayValueInEth >= totalDebtInEth) {
            // release all collateral when all debt is zero
            uint256 remainingCollateralAmount = IERC20(collateralAsset.collateralAssetWrapped).balanceOf(msg.sender);
            // debt fully repaid, send excess collateral to savings
            IAvaToken(collateralAsset.wrapped).mint_(
                msg.sender,
                remainingCollateralAmount,
                0,
                collateralAsset.overallExchangeRate
            );
        }

        // general rebalancing
        IAvaToken(collateralAsset.wrapped).supplyLiquidityVault(_debtAsset, addressesProvider.getLiquidityVault(), collateralAsset.savingsLiquidityBufferFactor);
        ICollateralToken(collateralAsset.wrapped).supplyLiquidityVault(_debtAsset, addressesProvider.getLiquidityVault(), collateralAsset.collateralLiquidityBufferFactor);

        // allows borrower to withdraw collateral on 0 debt balance
        // can happen on full liquidations
        IDebtToken(debtAsset.debtWrappedAsset).burn(msg.sender, repayAmount, debtAsset.borrowExchangeRate);
    }

    // tracks lendable deposit assets (deposits - bridged deposits)
    function updateTotalDepositsLendable(address asset, uint256 amountAdded, uint256 amountRemoved) external override {
        PoolAsset storage poolAsset = poolAssets[asset];
        poolAsset.totalDepositsLendable = poolAsset.totalDepositsLendable.add(amountAdded).sub(amountRemoved);
    }

    /**
     * @dev Liquidates a borrowers debt position and releases amount plus bonus to liquidator
     * @param borrower Account holding debt positions
     * @param debtAssets List of borrower debt position to liquidate
     * @param repayAmounts Amounts of each debtAsset to repay
     * @param collateralAssets Borrowers collateral assets to receive back
     **/
    function liquidationCall(
        address borrower,
        address[] memory debtAssets,
        uint256[] memory repayAmounts,
        address[] memory collateralAssets
    ) external whenNotPaused {

        for (uint256 i = 0; i < repayAmounts.length; i++) {
            PoolStorage.PoolAsset storage debtAsset = poolAssets[debtAssets[i]];

            PoolLogic.accrueInterest(
                debtAsset
            );

            PoolStorage.PoolAsset storage collateralAsset = poolAssets[collateralAssets[i]];

            PoolLogic.accrueInterest(
                collateralAsset
            );

        }

        ILiquidationCaller(addressesProvider.getLiquidationCaller()).liquidationCall(
            borrower,
            msg.sender,
            debtAssets,
            repayAmounts,
            collateralAssets
        );

    }


    // for PoolAssetData.sol
    function getPoolAssetData(address asset)
        external
        view
        override
        returns (PoolStorage.PoolAsset memory)
    {
        return poolAssets[asset];
    }

    /* function getMinPartialLiquidationValueInEth(address asset) external view override returns (uint256) {
        return minPartialLiquidationValueInEth;
    } */

    /* function getUserData(address user)
        external
        view
        override
        returns (PoolStorage.UserData memory)
    {
        return usersData[user];
    } */


    modifier onlyPoolAdmin() {
        require(msg.sender == addressesProvider.getPoolAdmin());
        _;
    }

    modifier onlyCollateralTokenFactory() {
        require(msg.sender == addressesProvider.getCollateralTokenFactory());
        _;
    }

    modifier onlySavingsTokenFactory() {
        require(msg.sender == addressesProvider.getSavingsTokenFactory());
        _;
    }


    modifier onlyDebtTokenFactory() {
        require(msg.sender == addressesProvider.getDebtTokenFactory());
        _;
    }

    function updateIsBorrowing(address user, address asset, bool val) private {
        usersData[user][asset].isBorrowing = val;
    }

    function updateLastRepayTimestamp(address user, address asset, uint256 _timestamp) private {
        usersData[user][asset].lastRepayTimestamp = _timestamp;
    }

    // get collateralAssets

    function updateLtv(address asset, uint256 _ltv) external onlyPoolAdmin {
        poolAssets[asset].ltv = _ltv;
    }

    function updateCtv(address asset, uint256 _ctd) external onlyPoolAdmin {
        poolAssets[asset].ctd = _ctd;
    }

    function updateReserve(address asset, address _reserve) external onlyPoolAdmin {
        poolAssets[asset].reserve = _reserve;
    }

    function updateReserveFactor(address asset, uint256 _reserveFactor) external onlyPoolAdmin {
        poolAssets[asset].reserveFactor = _reserveFactor;
    }

    function updateIsOn(address asset, bool _isActive) external onlyPoolAdmin {
        poolAssets[asset].on = _isActive;
    }

    function updateCollateralInterestRateFactor(address asset, uint256 _collateralExchangeRateFactor) external onlyPoolAdmin {
        poolAssets[asset].collateralInterestRateFactor = _collateralExchangeRateFactor;
    }

    function updateDebtInterestRateFactor(address asset, uint256 _debtInterestRateFactor) external onlyPoolAdmin {
        poolAssets[asset].debtInterestRateFactor = _debtInterestRateFactor;
    }

    function updateDepositsSuppliedInterestRateFactor(address asset, uint256 _depositsSuppliedInterestRateFactor) external onlyPoolAdmin {
        poolAssets[asset].depositsSuppliedInterestRateFactor = _depositsSuppliedInterestRateFactor;
    }

    function updateRouter(address asset, address _router) external onlyPoolAdmin {
        poolAssets[asset].router = _router;
    }

    function updateExchangeRateData(address asset, address _exchangeRateData) external onlyPoolAdmin {
        poolAssets[asset].exchangeRateData = _exchangeRateData;
    }

    function updateMaxCtdLiquidationThreshold(address asset, uint256 _maxCtdLiquidationThreshold) external onlyPoolAdmin {
        poolAssets[asset].maxCtdLiquidationThreshold = _maxCtdLiquidationThreshold;
    }

    /* function updatePoolAssetData(address asset, uint256 _param, uint256 _id) external onlyPoolAdmin {
        poolAssets[asset].depositsSuppliedInterestRateFactor = _depositsSuppliedInterestRateFactor;
    } */


    /* function initRewards(
        address rewardsBase,
        address wrapped
    ) external override onlyPoolAdmin {
        IRewardsTokenBase(wrapped).setRewards(
            rewardsBase
        );
    } */

    function initCollateralToken(
        address asset,
        address wrapped,
        address router,
        address exchangeRateData,
        uint256 routerMinSupplyRedeemAmount,
        uint256 routerMaxSupplyRedeemAmount,
        uint256 collateralInterestRateFactor,
        uint256 ctd, // collateral to debt
        bool isRoutable
    ) external onlyCollateralTokenFactory override {
        PoolAsset storage collateralAsset = poolAssets[asset];

        if (!collateralAsset.isCollateral) {
            collateralAssetsCount += 1;
        }

        PoolLogic.initCollateralToken(
            collateralAsset, // struct
            asset, // underlying
            wrapped, // collateral asset
            router,
            exchangeRateData,
            routerMinSupplyRedeemAmount,
            routerMaxSupplyRedeemAmount,
            collateralInterestRateFactor,
            ctd,
            isRoutable
        );

        addPoolAssetToListInternal(asset);
        emit CollateralTokenInit(
            asset,
            wrapped
        );
    }

    function initSavingsToken(
        address asset,
        address wrapped,
        address router,
        address exchangeRateData,
        uint256 routerMinSupplyRedeemAmount,
        uint256 depositsSuppliedInterestRateFactor,
        bool isRoutable
    ) external onlySavingsTokenFactory override {
        PoolAsset storage poolAsset = poolAssets[asset];
        // require to not init > 1
        if (!poolAsset.isSavings) {
            savingsAssetsCount += 1;
        }

        PoolLogic.initSavingsToken(
            poolAsset,
            asset,
            wrapped,
            router,
            exchangeRateData,
            routerMinSupplyRedeemAmount,
            depositsSuppliedInterestRateFactor,
            isRoutable
        );
        addPoolAssetToListInternal(asset);
        /* addSavingsAssetToListInternal(asset); */
        emit SavingsTokenInit(
            asset,
            wrapped
        );
    }

    function initDebtToken(
        address asset,
        address debtWrappedAsset,
        uint256 debtInterestRateFactor,
        uint256 ltv
    ) external onlyDebtTokenFactory override {
        PoolAsset storage poolAsset = poolAssets[asset];
        if (!poolAsset.isDebt) {
            debtAssetsCount += 1;
        }
        PoolLogic.initDebtToken(
            poolAsset,
            debtWrappedAsset,
            debtInterestRateFactor,
            ltv
        );
    }

    function addPoolAssetToListInternal(address asset) internal {
        uint256 _poolAssetsCount = poolAssetsCount;
        bool poolAssetAlreadyAdded = false;
        for (uint256 i = 0; i < _poolAssetsCount; i++)
            if (poolAssetsList[i] == asset) {
                poolAssetAlreadyAdded = true;
            }
        if (!poolAssetAlreadyAdded) {
            poolAssetsList[poolAssetsCount] = asset;
            poolAssetsCount = _poolAssetsCount + 1;
        }
    }

}
