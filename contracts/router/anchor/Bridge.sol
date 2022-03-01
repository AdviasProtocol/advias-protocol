// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IBridge} from "./IBridge.sol";
import {IConversionRouterV2} from "./interfaces/IRouterV2.sol";
import {IRouterV2} from "./interfaces/IRouterV2.sol"; // anchor
import {ISwapper} from "../../interfaces/ISwapper.sol";
import {WadRayMath} from '../../libraries/WadRayMath.sol';
import {IPoolAddressesProvider} from '../../interfaces/IPoolAddressesProvider.sol';
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "hardhat/console.sol";

// swaps assets to UST to send to routere for deposit or redeem

/**
 * @title Bridge
 * @author Advias
 * @title Dynamic bridge to Ancchor
 */
contract Bridge is IBridge, Context {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;

    uint256 constant ONE  = 1e18;

    uint256 public bridgeFee;
    uint256 public minBridgeCost;
    uint256 public swapFee; // fee charged by swapping through anchor on withdraw
    uint256 public stabilityFee; // stabilityFee
    uint256 public sdtPrice; // price of SDT
    uint256 public uusdGasRate;
    uint256 public anchorGasTx; // amount gas anchor uses to mint aust

    modifier onlyRouter() {
        require(msg.sender == addressesProvider.getRouter());
        _;
    }

    modifier onlyPoolAdmin() {
        require(msg.sender == addressesProvider.getPoolAdmin());
        _;
    }


    // swap settings
    ISwapper public swapper;

    address public optRouter;

    IPoolAddressesProvider private addressesProvider;


    // flags
    bool public isDepositAllowed = true;
    bool public isRedemptionAllowed = true;

    IERC20 public aUST;
    uint256 public _aUSTdecimals = 18;
    IERC20 public UST;
    uint256 public _USTdecimals = 18;

    uint256 public ONE_YR;

    constructor(
        IPoolAddressesProvider _addressesProvider,
        address _optRouter,
        address _swapper, // in-house swappeer Not anchors
        address _ust,
        address _aust
    ) {
        addressesProvider = _addressesProvider;
        ONE_YR = 31536000;
        UST = IERC20(_ust);
        aUST = IERC20(_aust);
        setSwapper(_swapper);
        setOperationRouter(_optRouter);
        setDepositAllowance(true);
        setRedemptionAllowance(true);
        bridgeFee = uint256(1000000000000000); // terra bridge fee
        minBridgeCost = uint256(1000000000000000000); // $1.00

        swapFee = uint256(3000000000000000); // anchor eth swap fee through uniswap v2 | uint256(400000000000000) for mainnet through curve meta
        stabilityFee = uint256(3500000000000000); // anchor eth swap fee through uniswap v2 | uint256(400000000000000) for mainnet through curve meta
        sdtPrice = uint256(1240000000000000000); // $1.24 UST at deploy --- max stabilityFee cost
        uusdGasRate = uint256(150000000000000000); // 15c UST at deploy --- max stabilityFee cost
        anchorGasTx = uint256(1000000000000000000000000); // minting uses 1,000,000 gas at deploy
    }

    function updateOneYear(uint256 x) public onlyPoolAdmin {
        ONE_YR = x;
    }

    function setSwapper(address _swapper) public onlyPoolAdmin {
        swapper = ISwapper(_swapper);
    }

    function setOperationRouter(address _optRouter) public onlyPoolAdmin {
        optRouter = _optRouter;
        UST.safeIncreaseAllowance(optRouter, type(uint256).max);
        aUST.safeIncreaseAllowance(optRouter, type(uint256).max);
    }

    function setDepositAllowance(bool _allow) public onlyPoolAdmin {
        isDepositAllowed = _allow;
    }

    function setRedemptionAllowance(bool _allow) public onlyPoolAdmin {
        isRedemptionAllowed = _allow;
    }

    function setBridgeFee(uint256 _bridgeFee) public onlyPoolAdmin {
        bridgeFee = _bridgeFee;
    }

    function setSwapFee(uint256 _swapFee) public onlyPoolAdmin {
        swapFee = _swapFee;
    }

    function setTax(uint256 _stabilityFee) public onlyPoolAdmin {
        stabilityFee = _stabilityFee;
    }

    function getBridgeFee() public view override returns (uint256) {
        return bridgeFee;
    }

    function getSwapFee() public view override returns (uint256) {
        return swapFee;
    }

    function getTax() public view override returns (uint256) {
        return stabilityFee;
    }

    // only accepts aUST
    function wrapped() public view override returns (address) {
        return address(aUST);
    }

    struct Router {
        address router;
        bool on;
    }

    uint256 internal routersCount;
    mapping(uint256 => address) public routersList;
    mapping(address => Router) public routers;

    /**
     * @dev Adds underlying asset to accept
     **/
    function addRouter(address _router) public onlyPoolAdmin {
        Router storage router = routers[_router];
        router.router = _router;
        router.on = true;
        addRouterToListInternal(_router);
    }

    function addRouterToListInternal(address router) internal {
        uint256 _routersCount = routersCount;
        bool routerAlreadyAdded = false;
        for (uint256 i = 0; i < _routersCount; i++)
            if (routersList[i] == router) {
                routerAlreadyAdded = true;
            }
        if (!routerAlreadyAdded) {
            routersList[routersCount] = router;
            routersCount = _routersCount + 1;
        }
    }

    /**
     * @dev Deposits UST into Anchor and returns AUST
     * @param _fromAsset Address to blacklist
     * @param _amount Amount to transfer in
     * @param _minAmountOut Minimum amount required to receive back from swap
     * @param to Address to send AUST to
     */
    function deposit(address _fromAsset, uint256 _amount, uint256 _minAmountOut, address to)
        public
        override
        onlyRouter
        returns (uint256)
    {
        require(isDepositAllowed, "ConversionPool: deposit not stopped");

        UST.safeTransferFrom(_msgSender(), address(this), _amount);

        // check swap in amount
        // send to optRouter
        // router then sends to `to`
        IConversionRouterV2(optRouter).depositStable(to, _amount);

        return depositAmountMinusFees(_amount);
    }

    // update decimals before calling to ust
    function depositAmountMinusFees(uint256 amount) public view override returns (uint256) {
      // eth ---> shuttle ---> terra

      // est amount landed in anchor after all fees - Bridge, Terra Tax
      // 100 * .001 = .1
      uint256 _bridgeFee = amount.wadMul(bridgeFee);
      if (_bridgeFee < minBridgeCost) {
          // if .1 > 1.0
          // _bridgeFee = 1.0
          _bridgeFee = minBridgeCost;
      }
      // after bridge
      // 100 - 1 = 99

      uint256 bridgedAmount = amount.sub(_bridgeFee);

      // 99 * .0035 = 0.3465
      uint256 _stabilityFee = bridgedAmount.wadMul(stabilityFee);


      if (_stabilityFee > sdtPrice) {
          // if 0.3465 > 1.24
          // _stabilityFee = 0.3465
          _stabilityFee = sdtPrice;
      }
      // 100 - 1 - 0.3465 = 98.6535
      return amount.sub(_bridgeFee).sub(_stabilityFee);

    }

    // _amount is in aust decimals - same as ust
    // amountReturned decimals

    /**
     * @dev Redeems AUST and returns UST or _toAsset
     * @param _toAsset Address to blacklist
     * @param _amount Amount to transfer in
     * @param to Address to send AUST to
     */
    function redeem(address _toAsset, uint256 _amount, address to) public override onlyRouter returns (uint256) {
        require(isRedemptionAllowed, "Error: redemption not allowed");
        console.log("in v2 redeem start");

        // transfer aUST in
        aUST.safeTransferFrom(_msgSender(), address(this), _amount);

        console.log("in v2 redeem after safeTransferFrom");

        uint256 amountReturned = _amount;
        // redeem aUST for UST and then swap for _toAsset
        // if user has avaDAI, swap to DAI through ethanchor
        // this is a bridge event.  Expect delays and risk
        // all swapping happens at ethanchor
        if (address(UST) != _toAsset) {
            // swap to _toAsset
            // this takes aUST and gets back asset to `to`
            IConversionRouterV2(optRouter).redeemStable(
                to, // operator
                _amount, // swap out amount aust -> ust -> _toAsset
                address(swapper), // curve
                _toAsset // dai
            );
            // adjust for swap fees
            // assume amount of _toAsset token returned from aust
            // this is done by anchor
            // terra -> shuttle -> eth -> swap -> to
            amountReturned = redeemWithSwapAmountMinusFees(_toAsset, _amount);
            console.log("in redeem", amountReturned);

        } else {
            // this method swaps aust for ust
            IRouterV2(optRouter).redeemStable(
                to, // operator
                _amount // swap out amount
            );

            amountReturned = redeemAmountMinusFees(amountReturned);
        }

        return amountReturned;
    }

    /**
     * @dev Redeems AUST and returns UST or _toAsset with no requirements
     * This is to be used if redeem is not required but will be called
     * @param _toAsset Asset to have anchor swap to
     * @param _amount Amount to transfer in
     * @param to Address to send AUST to
     */
    function redeemNR(address _toAsset, uint256 _amount, address to) public override onlyRouter returns (uint256) {
        if (!isRedemptionAllowed) {
            return 0;
        }

        // transfer aUST in
        aUST.safeTransferFrom(_msgSender(), address(this), _amount);
        /* try aUST.safeTransferFrom(_msgSender(), address(this), _amount) {
            // continue
        } catch {
            return 0;
        } */

        uint256 amountReturned = _amount;
        // redeem aUST for UST and then swap for _toAsset
        // if user has avaDAI, swap to DAI through ethanchor
        // this is a bridge event.  Expect delays and risk
        // all swapping happens at ethanchor
        if (address(UST) != _toAsset) {
            // swap to _toAsset
            // this takes aUST and gets back _toAsset to `to`
            /* IConversionRouterV2(optRouter).redeemStable(
                to, // operator
                _amount, // swap out amount aust -> ust -> _toAsset
                address(swapper), // curve
                _toAsset // dai
            ); */
            try IConversionRouterV2(optRouter).redeemStable(
                    to, // operator
                    _amount, // swap out amount aust -> ust -> _toAsset
                    address(swapper), // curve
                    _toAsset // dai
                )
            {
              // continue
            } catch {
                return 0;
            }

            // adjust for swap fees
            // assume amount of _toAsset token returned from aust
            // this is done by anchor
            // terra -> shuttle -> eth -> swap -> to
            amountReturned = redeemWithSwapAmountMinusFees(_toAsset, _amount);
        } else {
            // this method swaps aust for ust
            /* IRouterV2(optRouter).redeemStable(
                to, // operator
                _amount // swap out amount
            ); */

            try IRouterV2(optRouter).redeemStable(
                    to, // operator
                    _amount // swap out amount
                )
            {
              // continue
            } catch {
                return 0;
            }


            amountReturned = redeemAmountMinusFees(amountReturned);
        }

        return amountReturned;
    }


    function redeemAmountMinusFees(uint256 amount) public view override returns (uint256) {
        // terra ---> shuttle ---> eth

        uint256 _stabilityFee = amount.wadMul(stabilityFee);
        if (_stabilityFee > sdtPrice) {
            _stabilityFee = sdtPrice;
        }
        amount = amount.sub(_stabilityFee);

        // twice on withdraw
        _stabilityFee = amount.wadMul(stabilityFee);
        if (_stabilityFee > sdtPrice) {
            _stabilityFee = sdtPrice;
        }
        amount = amount.sub(_stabilityFee);

        // then bridge back to ethereum
        uint256 _bridgeFee = amount.wadMul(bridgeFee);
        if (_bridgeFee < minBridgeCost) {
            _bridgeFee = minBridgeCost;
        }
        return amount.sub(_bridgeFee);
    }

    // amount is adj to ust decimal in avatoken before calling redeem
    function redeemWithSwapAmountMinusFees(address _toAsset, uint256 amount) public view returns (uint256) {
        // terra ---> shuttle ---> eth
        uint256 _stabilityFee = amount.wadMul(stabilityFee);
        if (_stabilityFee > sdtPrice) {
            _stabilityFee = sdtPrice;
        }
        amount = amount.sub(_stabilityFee);

        // twice on withdraw
        _stabilityFee = amount.wadMul(stabilityFee);
        if (_stabilityFee > sdtPrice) {
            _stabilityFee = sdtPrice;
        }
        amount = amount.sub(_stabilityFee);

        // then bridge back to ethereum
        uint256 _bridgeFee = amount.wadMul(bridgeFee);
        if (_bridgeFee < minBridgeCost) {
            _bridgeFee = minBridgeCost;
        }
        // get amount bacck from uniswap including fees
        // mocks what anchor will do when swapping from wUST to _toAsset
        return swapper.getAmountOutMin(
            address(UST),
            _toAsset, // non-ust
            amount.sub(_bridgeFee)
        );
    }
}
