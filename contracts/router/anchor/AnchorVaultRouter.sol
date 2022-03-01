// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import {IConversionRouterV2} from "./interfaces/IRouterV2.sol";
import {IRouterV2} from "./interfaces/IRouterV2.sol";
import {WadRayMath} from '../../libraries/WadRayMath.sol';
import {IPoolAddressesProvider} from '../../interfaces/IPoolAddressesProvider.sol';
import {IAnchorVaultRouter} from "./IAnchorVaultRouter.sol";
import {ILocalVault} from '../../interfaces/ILocalVault.sol';

/**
 * @title AnchorVaultRouter
 * @author Advias
 * @title Responsible for calling to anchor vault
 */
contract AnchorVaultRouter is IAnchorVaultRouter {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;

    bool public routerOpen;

    IPoolAddressesProvider private addressesProvider;

    IERC20 private AUST;
    IERC20 private UST;
    uint256 public AUSTdecimals = 18;
    uint256 public USTdecimals = 18;
    address public router;

    /**
     * @dev Adds underlying asset to accept
     **/
    function addRouter(address _router) public onlyPoolAdmin {
        router = _router;
    }

    constructor(
        IPoolAddressesProvider _addressesProvider,
        address _AUST,
        address _UST
    ) {
        addressesProvider = _addressesProvider;
        routerOpen = true;
        AUST = IERC20(_AUST);
        UST = IERC20(_UST);
    }

    function setVaultOpen(bool _b) public onlyPoolAdmin {
        routerOpen = _b;
    }

    modifier onlyPoolAdmin() {
        require(msg.sender == addressesProvider.getPoolAdmin());
        _;
    }

    modifier onlyRouter() {
        require(msg.sender == router);
        _;
    }

    function _routerOpen() external view returns (bool) {
        return routerOpen;
    }

    // check if enough aust if x_amount of ust deposited
    function vaultOpenAndWrappedAvailable(uint256 ustAmount) external view returns (bool) {
        return ILocalVault(addressesProvider.getAnchorVault()).vaultOpenAndWrappedAvailable(ustAmount);
    }

    // check if enough ust if x_amount of aust redeemed
    function vaultOpenAndUnderlyingAvailable(uint256 austAmount) external view returns (bool) {
        return ILocalVault(addressesProvider.getAnchorVault()).vaultOpenAndUnderlyingAvailable(austAmount);
    }


    function deposit(address asset, uint256 _amount, uint256 _minAmountOut, address to)
        public
        override
        onlyRouter
        returns (uint256)
    {
        require(routerOpen, "Error: Vault closed");

        UST.safeTransferFrom(msg.sender, address(this), _amount);

        ILocalVault(addressesProvider.getAnchorVault()).deposit(_amount, 0, to);

        return _amount;
    }

    function redeem(address asset, uint256 _amount, address to) public override onlyRouter returns (uint256) {
        /* require(isRedemptionAllowed, "Error: redemption not allowed"); */
        require(routerOpen, "Error: Vault closed");

        // transfer aUST in
        AUST.safeTransferFrom(msg.sender, address(this), _amount);

        ILocalVault(addressesProvider.getAnchorVault()).redeem(_amount, to, asset);

        uint256 ust = UST.balanceOf(address(this));

        return ust;
    }

    /// no revert version
    function redeemNR(address asset, uint256 _amount, address to) public override onlyRouter returns (uint256) {
        if (!routerOpen) {
            return 0;
        }
        AUST.safeTransferFrom(msg.sender, address(this), _amount);

        ILocalVault(addressesProvider.getAnchorVault()).redeemNR(_amount, to, asset);

        uint256 ust = UST.balanceOf(address(this));

        return ust;
    }

}
