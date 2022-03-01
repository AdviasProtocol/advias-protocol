// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";


import {IExchangeRateFeeder} from "./interfaces/IExchangeRateFeeder.sol";
import {IConversionRouterV2} from "./interfaces/IRouterV2.sol";
import {IRouterV2} from "./interfaces/IRouterV2.sol";
import {WadRayMath} from '../../libraries/WadRayMath.sol';
import {IPoolAddressesProvider} from '../../interfaces/IPoolAddressesProvider.sol';
import {IPoolAssetData} from '../../interfaces/IPoolAssetData.sol';

import {IExchangeRateData} from '../../interfaces/IExchangeRateData.sol';
import {ISwapper} from "../../interfaces/ISwapper.sol";
import {ILocalVault} from '../../interfaces/ILocalVault.sol';
import "hardhat/console.sol";

/**
 * @title AnchorVault
 * @author Advias
 * @title Asset vault that holds AUST and UST to accept and transfer AUST and UST
 * The purpose is to avoid bridging and use this vault when available on savings avaTokens
 */

contract AnchorVault is ILocalVault {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;

    bool public vaultOpen;

    IPoolAddressesProvider private addressesProvider;
    IPoolAssetData private poolAssetData;
    IExchangeRateData private exchangeRateData;
    ISwapper private swapper;

    IERC20 private AUST;
    IERC20 private UST;

    address private anchorVaultRouter;

    constructor(
        IPoolAddressesProvider _addressesProvider,
        IExchangeRateData _exchangeRateData,
        address _swapper,
        address _anchorVaultRouter,
        address _AUST,
        address _UST
    ) {
        addressesProvider = _addressesProvider;
        poolAssetData = IPoolAssetData(addressesProvider.getPoolAssetData());
        exchangeRateData = _exchangeRateData;
        vaultOpen = true;
        setSwapper(_swapper);
        AUST = IERC20(_AUST);
        UST = IERC20(_UST);
        setAnchorVaultRouter(_anchorVaultRouter);
    }

    function setVaultOpen(bool _b) public onlyPoolAdmin {
        vaultOpen = _b;
    }

    modifier onlyAnchorVaultRouter() {
        require(msg.sender == anchorVaultRouter);
        _;
    }

    modifier onlyPoolAdmin() {
        require(msg.sender == addressesProvider.getPoolAdmin());
        _;
    }

    function setAnchorVaultRouter(address _anchorVaultRouter) public onlyPoolAdmin {
        anchorVaultRouter = _anchorVaultRouter;
        UST.safeIncreaseAllowance(_anchorVaultRouter, type(uint256).max);
        AUST.safeIncreaseAllowance(_anchorVaultRouter, type(uint256).max);
    }

    function setPoolAssetData(address _poolAssetData) public onlyPoolAdmin {
        poolAssetData = IPoolAssetData(addressesProvider.getPoolAssetData());
    }

    function setSwapper(address _swapper) public onlyPoolAdmin {
        swapper = ISwapper(_swapper);
    }

    function getInterestData() public view returns (uint256, uint256) {
        return IExchangeRateData(poolAssetData.getExchangeRateData(address(UST))).getInterestData();
    }


    function _vaultOpen() external view returns (bool) {
        return vaultOpen;
    }

    // check if enough aust if x_amount of ust deposited
    function vaultOpenAndWrappedAvailable(uint256 ustAmount) external view override returns (bool) {
        bool open = true;
        if (vaultOpen == false) {
            open = false;
        }
        ( , uint256 ER) = getInterestData();
        uint256 austBalance = AUST.balanceOf(address(this));

        if (open &&
          austBalance.wadMul(ER) < ustAmount) {
            open = false;
        }

        return open;
    }

    // check if enough ust if x_amount of aust redeemed
    function vaultOpenAndUnderlyingAvailable(uint256 austAmount) external view override returns (bool) {
        bool open = true;
        if (vaultOpen == false) {
            open = false;
        }
        ( , uint256 ER) = getInterestData();
        uint256 ustBalance = UST.balanceOf(address(this));

        if (open &&
          ustBalance < austAmount.wadMul(ER)) {
            open = false;
        }


        return open;
    }


    function deposit(uint256 _amount, uint256 _minAmountOut, address to)
        external
        onlyAnchorVaultRouter
        override
    {
        require(vaultOpen, "Error: Vault closed");

        UST.safeTransferFrom(msg.sender, address(this), _amount);

        ( , uint256 ER) = getInterestData();

        uint256 austBack = _amount.wadMul(ER);

        AUST.safeTransfer(to, austBack);
    }


    function redeem(uint256 _amount, address to, address _outAsset)
        external
        onlyAnchorVaultRouter
        override
    {
        // transfer aUST in
        AUST.safeTransferFrom(msg.sender, address(this), _amount);

        ( , uint256 ER) = getInterestData();

        uint256 ustValue = _amount.wadMul(ER);

        if (_outAsset != address(0) && _outAsset != address(UST)) {
            swapper.swapToken(
                address(UST),
                _outAsset,
                ustValue,
                0,
                to
            );
        } else {
            UST.safeTransfer(to, ustValue);
        }
    }

    function redeemNR(uint256 _amount, address to, address _outAsset)
        external
        onlyAnchorVaultRouter
        override
    {
        // transfer aUST in
        AUST.safeTransferFrom(msg.sender, address(this), _amount);

        ( , uint256 ER) = getInterestData();

        uint256 ustValue = _amount.wadMul(ER);

        if (_outAsset != address(0) && _outAsset != address(UST)) {
            swapper.swapToken(
                address(UST),
                _outAsset,
                ustValue,
                0,
                to
            );
        } else {
            UST.safeTransfer(to, ustValue);
        }
    }

}
