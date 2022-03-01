// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";


import {IAvaToken} from '../../interfaces/IAvaToken.sol';

import {WadRayMath} from '../../libraries/WadRayMath.sol';
import {IPoolAddressesProvider} from '../../interfaces/IPoolAddressesProvider.sol';
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IBridge} from "./IBridge.sol";
/* import {IAnchorVaultRouter} from "./IAnchorVaultRouter.sol"; */
import {ILocalVault} from '../../interfaces/ILocalVault.sol';

import {IRouter} from "../../interfaces/IRouter.sol";
import {ISwapper} from "../../interfaces/ISwapper.sol";
import "hardhat/console.sol";

/**
 * @title Router
 * Routers are designated for underlying/supplyWrapped vaults
 * @author Advias
 * @title Logic to bridge or use Anchor Vault
 * underlying/wrapped
 * This Router is for stable assets swapped to underlying if not underlying
 * Note: This is in-protocol implementation of our own router - Not Anchor router
 * Each asset can have many routers or one
 * This specific router is designed to only output one underlying asset but allow any asset to enter and swap to that underlying asset
 * 
 * Aggregation
 * This contract can be expanded into nodes of contracts to aggregate an asset to multiple protocols
 * The only important factor is that this contract is the main point of allocation to route assets outside of Advias Protocol
 * Getting balancing and exchagne rate data if done through ExchangeRateData.sol for scaling solutions
 */
contract AnchorRouter is IRouter {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;

    /* bool public vaultOpen; */
    address private bridge;
    address private localVault;

    IPoolAddressesProvider private addressesProvider;

    IERC20 private wrapped;
    uint256 private wrappedDecimals = 18;
    IERC20 private underlying;
    uint256 private underlyingDecimals = 18;

    /* address private anchorVaultRouter; */

    ISwapper private swapper;

    uint256 public defaultMinOutFactor = 995000000000000000;
    uint256 private defaultMinBridgeSupplyAmount = 10;
    uint256 private defaultMaxBridgeSupplyAmount = 10;

    struct RouterAsset {
        address asset;
        uint256 decimals;
        uint256 minBridgeSupplyAmount; // anchor has min bridge amount of 10 eth
        uint256 maxBridgeSupplyAmount; // anchor has min bridge amount of 10 eth
        uint256 minOutFactor; // swap logic for min percentage of swap amount to get back as wad
        address swapper; // scalability for new assets which may not be stable assets
        bool on;
    }

    uint256 internal routerAssetsCount;
    mapping(uint256 => address) public routerAssetsList;
    mapping(address => RouterAsset) public routerAssets;

    function _addRouterAssets(address[] memory assets) internal {
        addRouterAssets(assets);
    }

    function addRouterAssets(address[] memory assets) public onlyPoolAdmin {
        for (uint256 i = 0; i < assets.length; i++) {
            addRouterAsset(assets[i]);
        }
    }

    /**
     * @dev Adds underlying asset to accept
     **/
    function addRouterAsset(address asset) public onlyPoolAdmin {
        RouterAsset storage routerAsset = routerAssets[asset];
        uint256 assetDecimals = IERC20Metadata(asset).decimals();
        routerAsset.asset = asset;
        routerAsset.decimals = assetDecimals;
        routerAsset.minBridgeSupplyAmount = defaultMinBridgeSupplyAmount*(10**assetDecimals);
        routerAsset.maxBridgeSupplyAmount = defaultMaxBridgeSupplyAmount*(10**assetDecimals);
        routerAsset.minOutFactor = defaultMinOutFactor;
        routerAsset.on = true;
        addRouterAssetToListInternal(asset);
        IERC20(asset).safeIncreaseAllowance(address(swapper), type(uint256).max);
        IERC20(asset).approve(bridge, type(uint256).max);
        IERC20(asset).approve(localVault, type(uint256).max);
    }

    function addRouterAssetToListInternal(address asset) internal {
        uint256 _routerAssetsCount = routerAssetsCount;
        bool assetAlreadyAdded = false;
        for (uint256 i = 0; i < _routerAssetsCount; i++)
            if (routerAssetsList[i] == asset) {
                assetAlreadyAdded = true;
            }
        if (!assetAlreadyAdded) {
            routerAssetsList[routerAssetsCount] = asset;
            routerAssetsCount = _routerAssetsCount + 1;
        }
    }

    constructor(
        address _addressesProvider,
        /* address _anchorVaultRouter, */
        address _localVault,
        address _bridge,
        address _swapper,
        address[] memory assets,
        address _wrapped,
        address _underlying
    ) {
        wrapped = IERC20(_wrapped);
        underlying = IERC20(_underlying);
        addressesProvider = IPoolAddressesProvider(_addressesProvider);
        underlying.safeIncreaseAllowance(_localVault, type(uint256).max);
        wrapped.safeIncreaseAllowance(_localVault, type(uint256).max);
        underlying.safeIncreaseAllowance(_bridge, type(uint256).max);
        wrapped.safeIncreaseAllowance(_bridge, type(uint256).max);
        bridge = _bridge;
        localVault = _localVault;
        swapper = ISwapper(_swapper);
        addRouterAssets(assets);
    }

    modifier onlyPoolAdmin() {
        require(msg.sender == addressesProvider.getPoolAdmin());
        _;
    }


    function setSwapper(address _swapper) public onlyPoolAdmin {
        swapper = ISwapper(_swapper);
    }

    function setAddressesProvider(address _addressesProvider) public onlyPoolAdmin {
        addressesProvider = IPoolAddressesProvider(_addressesProvider);
    }

    function setAnchorVaultRouter(address _anchorVaultRouter) public onlyPoolAdmin {
        underlying.safeIncreaseAllowance(_anchorVaultRouter, type(uint256).max);
        wrapped.safeIncreaseAllowance(_anchorVaultRouter, type(uint256).max);
    }

    function setBridge(address _bridge) public onlyPoolAdmin {
        underlying.safeIncreaseAllowance(_bridge, type(uint256).max);
        wrapped.safeIncreaseAllowance(_bridge, type(uint256).max);
    }

    function setMinBridgeSupplyAmount(address asset, uint256 _minBridgeSupplyAmount) public onlyPoolAdmin {
        RouterAsset storage routerAsset = routerAssets[asset];
        routerAsset.minBridgeSupplyAmount = _minBridgeSupplyAmount;
    }

    function setMaxBridgeSupplyAmount(address asset, uint256 _maxBridgeSupplyAmount) public onlyPoolAdmin {
        RouterAsset storage routerAsset = routerAssets[asset];
        routerAsset.maxBridgeSupplyAmount = _maxBridgeSupplyAmount;
    }


    function setMinOutFactor(address asset, uint256 _minOutFactor) public onlyPoolAdmin {
        RouterAsset storage routerAsset = routerAssets[asset];
        routerAsset.minOutFactor = _minOutFactor;
    }

    function _underlyingAsset() public view override returns (address) {
        return address(underlying);
    }

    function _wrappedAsset() public view override returns (address) {
        return address(wrapped);
    }

    struct routerSupplyOnDepositSavingsParams {
        uint256 amountAdded;
    }

    /**
     * @dev Rebalance on deposits between wrapped and underlying to keep interest rate level with debt interest rate
     * This removes arbatrage as much as possible
     * First check if
     **/
     function getAllotAmountOnSupply(
        uint256 amountAdded, // 100
        address supplyWrapped,
        uint256 goalInterestRate, // the borrow rate and goal savings rate
        address debtWrapped,
        uint256 supplyInterestRate,
        uint256 minSupplyRequirementAmount,
        uint256 decimals // decimals of supply and debt wrapped asset - should match unerlying and be the same as eachother
    ) external view override returns (uint256) {
        console.log("getAllotAmountOnSupply amountAdded", amountAdded);
        console.log("getAllotAmountOnSupply supplyWrapped", supplyWrapped);
        console.log("getAllotAmountOnSupply goalInterestRate", goalInterestRate);
        console.log("getAllotAmountOnSupply debtWrapped", debtWrapped);
        console.log("getAllotAmountOnSupply supplyInterestRate", supplyInterestRate);
        console.log("getAllotAmountOnSupply minSupplyRequirementAmount", minSupplyRequirementAmount);
        console.log("getAllotAmountOnSupply decimals", decimals);

        routerSupplyOnDepositSavingsParams memory params;
        params.amountAdded = amountAdded;
        // 700

        uint256 amountRouted = IAvaToken(supplyWrapped).routerSuppliedTotalSupply();

        // how much annual yield are we already receiving from router
        // it's possible we are already covering the goal interest rate
        // if so, don't supply and send amountAdded to lendable
        uint256 routedYield = amountRouted.wadMul(supplyInterestRate);


        // total value
        // 1000 + 100 = 1100
        uint256 totalSupply = IERC20(supplyWrapped).totalSupply().add(params.amountAdded); // total amount of assets lends and bridge + amount

        // amount required repay (lends and router) to match debt APR
        // this is the minimum annual yield to accomplish
        // 1100 * .14 = 154
        uint256 amountToAchieve = totalSupply.wadMul(goalInterestRate);

        // repay amounts
        // 0
        uint256 totalDebtReturned = IERC20(debtWrapped).totalSupply().wadMul(goalInterestRate); // suedo debt returned yr (non-compounded)
        
        // just in case
        // if false, we send to lendable 
        if ((totalDebtReturned.add(routedYield)) > amountToAchieve) { return 0; }

        // difference to achieve
         // 154 - 0 = 154

        // amount needed to send to router to achieve difference

        // accounting to depositors interest rate factor
        // 154 / .2 = 770
        uint256 amountToSupplyToRouterToAchieveMatch = (amountToAchieve.sub(totalDebtReturned)).wadDiv(supplyInterestRate);

        uint256 amountBack = depositAmountMinusFees(amountToSupplyToRouterToAchieveMatch.mul(10**underlyingDecimals).div(10**decimals));

        amountBack = amountBack.mul(10**decimals).div(10**underlyingDecimals);

        // need to estimate fees for anchor due to interoperable bridging not taking place in same tx
        // this issue is combatted through:
        //  // estimating fees
        //  // interest rate factoring
        uint256 feesAmount = amountToSupplyToRouterToAchieveMatch.sub(amountBack);

        // 773.86390479824937351671708897541 = ((770 / (1-.001)) / (1-.003)) / (1-.001)

        uint256 amountToRouter = amountToSupplyToRouterToAchieveMatch.add(feesAmount);

        uint256 routerAmountToAdd = 0;
        if (amountToRouter > amountRouted){
            // 773.86390479824937351671708897541 - 700 = 73.86390479824937351671708897541
            routerAmountToAdd = amountToRouter.sub(amountRouted);
            if (routerAmountToAdd > params.amountAdded) {
                routerAmountToAdd = params.amountAdded;
            }
            if (routerAmountToAdd < minSupplyRequirementAmount) {
                routerAmountToAdd = 0;
            }
        }

        return routerAmountToAdd;
    }

    // function getAllotAmountOnSupply(
    //     uint256 amountAdded, // 100
    //     address supplyWrapped,
    //     uint256 goalInterestRate,
    //     address debtWrapped,
    //     uint256 supplyInterestRate,
    //     uint256 minSupplyRequirementAmount,
    //     uint256 decimals // decimals of supply and debt wrapped asset - should match unerlying and be the same as eachother
    // ) external view override returns (uint256) {
    //     console.log("getAllotAmountOnSupply amountAdded", amountAdded);
    //     console.log("getAllotAmountOnSupply supplyWrapped", supplyWrapped);
    //     console.log("getAllotAmountOnSupply goalInterestRate", goalInterestRate);
    //     console.log("getAllotAmountOnSupply debtWrapped", debtWrapped);
    //     console.log("getAllotAmountOnSupply supplyInterestRate", supplyInterestRate);
    //     console.log("getAllotAmountOnSupply minSupplyRequirementAmount", minSupplyRequirementAmount);
    //     console.log("getAllotAmountOnSupply decimals", decimals);

    //     routerSupplyOnDepositSavingsParams memory params;
    //     params.amountAdded = amountAdded;
    //     // 700

    //     uint256 amountRouted = IAvaToken(supplyWrapped).routerSuppliedTotalSupply();


    //     // total value
    //     // 1000 + 100 = 1100
    //     uint256 totalSupply = IERC20(supplyWrapped).totalSupply().add(params.amountAdded); // total amount of assets lends and bridge + amount

    //     // amount required repay (lends and router) to match debt APR
    //     // 1100 * .14 = 154
    //     uint256 amountToAchieve = totalSupply.wadMul(goalInterestRate);

    //     // repay amounts
    //     // 0
    //     uint256 totalDebtReturned = IERC20(debtWrapped).totalSupply().wadMul(goalInterestRate); // suedo debt returned yr (non-compounded)
    //     // just in case
    //     if (totalDebtReturned > amountToAchieve) { return 0; }

    //     // difference to achieve
    //      // 154 - 0 = 154

    //     // amount needed to send to router to achieve difference

    //     // accounting to depositors interest rate factor
    //     // 154 / .2 = 770
    //     uint256 amountToSupplyToRouterToAchieveMatch = (amountToAchieve.sub(totalDebtReturned)).wadDiv(supplyInterestRate);

    //     uint256 amountBack = depositAmountMinusFees(amountToSupplyToRouterToAchieveMatch.mul(10**underlyingDecimals).div(10**decimals));

    //     amountBack = amountBack.mul(10**decimals).div(10**underlyingDecimals);

    //     // need to estimate fees for anchor due to interoperable bridging not taking place in same tx
    //     // this issue is combatted through:
    //     //  // estimating fees
    //     //  // interest rate factoring
    //     uint256 feesAmount = amountToSupplyToRouterToAchieveMatch.sub(amountBack);

    //     // 773.86390479824937351671708897541 = ((770 / (1-.001)) / (1-.003)) / (1-.001)

    //     uint256 amountToRouter = amountToSupplyToRouterToAchieveMatch.add(feesAmount);

    //     uint256 routerAmountToAdd = 0;
    //     if (amountToRouter > amountRouted){
    //         // 773.86390479824937351671708897541 - 700 = 73.86390479824937351671708897541
    //         routerAmountToAdd = amountToRouter.sub(amountRouted);
    //         if (routerAmountToAdd > params.amountAdded) {
    //             routerAmountToAdd = params.amountAdded;
    //         }
    //         if (routerAmountToAdd < minSupplyRequirementAmount) {
    //             routerAmountToAdd = 0;
    //         }
    //     }

    //     return routerAmountToAdd;
    // }

    /**
     * @dev Rebalance on withdraws between wrapped and underlying to keep interest rate level with debt interest rate
     * Redeems x_amount on redeem from router from outside integrated protocols
     * This removes arbitrage as much as possible
     **/
    function getAllotAmountOnRedeem(
        uint256 amountToWithdraw,  // amount account withdraw
        address supplyWrapped,
        uint256 goalInterestRate, // the borrow rate and goal savings rate
        address debtWrapped,
        uint256 supplyInterestRate,
        uint256 minRedeemRequirementAmount,
        uint256 decimals
    ) external view override returns (uint256) {

        // current valuee routerd
        // 700
        // depositsSuppliedTotalSupply is in the in-house supplyWrapped asset decimals
        // meaning the decimals here are the underlying asset of the avasToken
        uint256 amountRouted = IAvaToken(supplyWrapped).routerSuppliedTotalSupply();

        // verify we have 
        // total value
        // 1000 - 100
        // 900

        uint256 totalSupply = IERC20(supplyWrapped).totalSupply(); // total amount of assets lends and bridge
        require(totalSupply >= amountToWithdraw, "Error: Withdraw amount too great");

        totalSupply = totalSupply.sub(amountToWithdraw); // total minus withdraw amount

        // amount required repay (lends and router) to match debt APR
        // 900 * .14 = 126
        uint256 amountToAchieve = totalSupply.wadMul(goalInterestRate);

        // repay amounts
        // 0
        uint256 totalDebtReturned = IERC20(debtWrapped).totalSupply().wadMul(goalInterestRate); // suedo debt returned yr (non-compounded)

        // just in case
        if (totalDebtReturned > amountToAchieve) { return 0; }

        // difference to achieve
        // 126 - 0 = 126
        uint256 amountSpreadToAchieve = amountToAchieve.sub(totalDebtReturned);

        // accounting to depositors interest rate factor
        // this is the amount that will need to be routerd to keep interest rate stable
        // 126 / .2 = 630
        uint256 amountToSupplyToRouterToAchieveMatch = amountSpreadToAchieve.wadDiv(supplyInterestRate);
        console.log("getAllotAmountOnRedeem amountToSupplyToRouterToAchieveMatch", amountToSupplyToRouterToAchieveMatch);

        uint256 routerRemoveToUser = 0;
        // if 700 > 630
        // then redeem some
        // else 0
        if (amountRouted >= amountToSupplyToRouterToAchieveMatch) {
            // 700 - 630 = 70
            // max to redeem to user (if they aree withdrawing this amount or more)
            routerRemoveToUser = amountRouted.sub(amountToSupplyToRouterToAchieveMatch);

            // if the interest rate is too high and we need
            // to remove more to adjust the rate
            // then remove user full withdraw amount
            if (routerRemoveToUser > amountToWithdraw) {
                routerRemoveToUser = amountToWithdraw;
            }
            if (routerRemoveToUser < minRedeemRequirementAmount) {
                routerRemoveToUser = 0;
            }
        }
        // example
        // user gets ~70 from router and 30 from tokenization contract
        // the amount back from the bridge will not be guaranteed and this is a risk a user will ultimately take
        return routerRemoveToUser;
    }

    /**
     * @dev Deposits underlying to Anchor or Vault and returns wrapped to `to`
     * @param asset Asset to transfer in
     * @param _amount Amount to transfer in
     * @param _minAmountOut Min amount our on swap
     * @param to Address to send wrapped to
     * TRUE/FALSE is local was used, amountBack How much underlying was sent out after fees
     */
    function deposit(address asset, uint256 _amount, uint256 _minAmountOut, address to) public override returns (bool, uint256) {
        RouterAsset storage routerAsset = routerAssets[asset];
        // ensure the asset is initialized and on
        require(routerAsset.on, "Error: Router asset not active");

        IERC20(asset).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 amountBack = _amount;

        // if not UST, or main asset, swap to it
        if (address(underlying) != routerAsset.asset) {
            // swap to underlying
            swapper.swapToken(
                routerAsset.asset,
                address(underlying),
                _amount,
                _minAmountOut,
                address(this)
            );
        }

        // get the amount back from the swap
        // assets should never be stuck in here so this isn't an issue
        _amount = underlying.balanceOf(address(this));

        // check if vault has enough, else use bridge
        bool usedVault = false;
        if (ILocalVault(addressesProvider.getAnchorVault()).vaultOpenAndWrappedAvailable(_amount)) {
            // this is the vault where we keep the yield asset to avoid bridging as a first attempt
            // this also yields the protocol income
            // non-bridge assets will not need this as much and may not be coded in
            /* amountBack = IAnchorVaultRouter(anchorVaultRouter).deposit(asset, _amount, _minAmountOut, to); */
            ILocalVault(localVault).deposit(_amount, 0, to);
            usedVault = true;
        } else {
            // use the bridge
            amountBack = IBridge(bridge).deposit(asset, _amount, _minAmountOut, to);
        }
        return (usedVault, amountBack);
    }

    /**
     * @dev Deposits wrapped to Anchor or Vault and returns underlying to `to`
     * @param _amount Amount wrapped to transfer in
     * @param to Address to send wrapped to
     * @param _outAsset Asset to have anchor swap to
     */
    function redeem(uint256 _amount, address to, address _outAsset) public override returns (uint256) {
        RouterAsset storage routerAsset = routerAssets[_outAsset];
        require(routerAsset.on, "Error: Router asset not active");
        // tranfer in aust to swap to ust
        wrapped.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 amountBack = _amount;
        // check if vault has enough, else use bridge
        // bool usedVault = false;
        if (ILocalVault(addressesProvider.getAnchorVault()).vaultOpenAndUnderlyingAvailable(_amount)) {
            // if non-UST asset, local vault will attempt a swap
            ILocalVault(localVault).redeem(_amount, to, routerAsset.asset);
            amountBack = underlying.balanceOf(address(this));
            // usedVault = true;
        } else {
            amountBack = IBridge(bridge).redeem(routerAsset.asset, _amount, to);
        }
        return amountBack;
    }

    /**
     * @dev redeem with no require statements
     * Used when not needed but will be called
     * @param _amount Amount wrapped to transfer in
     * @param to Address to send wrapped to
     * @param _outAsset Asset to have anchor swap to
     */
    function redeemNR(uint256 _amount, address to, address _outAsset) public override returns (uint256) {
        RouterAsset storage routerAsset = routerAssets[_outAsset];
        if (routerAsset.on || _amount < 10e18) { return 0; }
        uint256 amountBack;
        // check if vault has enough, else use bridge
        if (ILocalVault(addressesProvider.getAnchorVault()).vaultOpenAndUnderlyingAvailable(_amount)) {
            /* amountBack = IAnchorVaultRouter(anchorVaultRouter).redeemNR(_outAsset, _amount, to); */
            ILocalVault(localVault).redeem(_amount, to, _outAsset);
            amountBack = underlying.balanceOf(address(this));
        } else {
            amountBack = IBridge(bridge).redeem(_outAsset, _amount, to);
        }
        return amountBack;

    }

    /**
    * calculate the amount back after supplying
    * bridging will likely have fees due to platform who has fees
     */
    function depositAmountMinusFees(uint256 _amount) public view override returns (uint256) {
        uint256 amountBack;
        if (ILocalVault(addressesProvider.getAnchorVault()).vaultOpenAndUnderlyingAvailable(_amount)) {
            amountBack = _amount;
        } else {
            amountBack = IBridge(bridge).depositAmountMinusFees(_amount);
        }
        return amountBack;
    }


}
