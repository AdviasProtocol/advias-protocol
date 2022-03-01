// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import {ISwapper} from "../interfaces/ISwapper.sol";
import "hardhat/console.sol";

interface ICurve {
    function N_COINS() external view returns (int128);

    function BASE_N_COINS() external view returns (int128);

    function coins(uint256 i) external view returns (address); // pool

    function base_coins(uint256 i) external view returns (address); // base_pool

    function get_dy(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256);

    function get_dy_underlying(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256);

    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external returns (uint256);

    function exchange_underlying(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external returns (uint256);
}

/**
 * @title CurveSwapper
 * @author Advias
 * @title Main swapping contract for protocol with Curve
 */
contract CurveSwapper is ISwapper, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    struct Route {
        address[] pools;
        int128[] indexes;
    }

    mapping(address => mapping(address => Route)) private routes;

    function getRoute(address _from, address _to)
        public
        view
        returns (Route memory)
    {
        return routes[_from][_to];
    }

    /* constructor(

    ) {

    }

    // mainnet
    // 0 0x6B175474E89094C44Da98b954EedeAC495271d0F DAI
    // 1 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 USDC
    // 2 0xdAC17F958D2ee523a2206206994597C13D831ec7 USDT
    function updateRoute(

    ) public onlyOwner {

    } */

    /*
    setRoute(
        0xa47c8bf37f92aBed4A126BDA807A7b7498661acD,
        0x6B175474E89094C44Da98b954EedeAC495271d0F,
        [0x890f4e345B1dAED0367A877a1612f86A1f86985f],
        [0xa47c8bf37f92aBed4A126BDA807A7b7498661acD, 0x6B175474E89094C44Da98b954EedeAC495271d0F],
        [0, 0]
    )
    setRoute(
        0x6b175474e89094c44da98b954eedeac495271d0f,
        0xa47c8bf37f92aBed4A126BDA807A7b7498661acD,
        [0x890f4e345B1dAED0367A877a1612f86A1f86985f],
        [0x6b175474e89094c44da98b954eedeac495271d0f, 0xa47c8bf37f92aBed4A126BDA807A7b7498661acD],
        [0, 0]
    )

   */

    // base_coins
    // 0 - 0xa47c8bf37f92aBed4A126BDA807A7b7498661acD - UST
    // 1 - 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490 - Crv

    // coins:
    // 0 - 0x6B175474E89094C44Da98b954EedeAC495271d0F - DAI
    // 1 - 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 - USDC
    // 2 - 0xdAC17F958D2ee523a2206206994597C13D831ec7 - USDT

    function setRoute(
        address _from, // coins
        address _to, // base_coins
        address[] memory _pools, // 0x890f4e345B1dAED0367A877a1612f86A1f86985f
        address[] memory _tokens,
        int128[] memory _indexes
    ) public onlyOwner {
        require(_indexes.length >= 2, "CurveSwapper: INVALID_PATH");
        require(
            _pools.length.mul(2) == _indexes.length,
            "CurveSwapper: INVALID_LENGTH"
        );
        Route storage route = routes[_from][_to];
        route.pools = _pools;
        route.indexes = _indexes;

        for (uint256 i = 0; i < route.pools.length; i++) {
            if (IERC20(_tokens[i]).allowance(address(this), _pools[i]) == 0) {
                IERC20(_tokens[i]).safeApprove(_pools[i], type(uint256).max);
            }
        }
    }

    /*
      @param i Index value for the underlying coin to send
      @param j Index valie of the underlying coin to recieve
      @param dx Amount of `i` being exchanged
      @param min_dy Minimum amount of `j` to receive
      @return Actual amount of `j` received
    */
    function swapToken(
        address _from, // swap from
        address _to, // swap to
        uint256 _amount,
        uint256 _minAmountOut,
        address _beneficiary // ignore
    ) public override {
        IERC20(_from).safeTransferFrom(msg.sender, address(this), _amount);


        uint256 bal = IERC20(_from).balanceOf(address(this));
        uint256 allow = IERC20(_from).allowance(address(this), address(0x890f4e345B1dAED0367A877a1612f86A1f86985f));

        console.log("swapToken bal", bal);
        console.log("swapToken _to", _to);
        console.log("swapToken _from", _from);
        console.log("swapToken allow", allow);


        Route memory route = routes[_from][_to];


        require(route.pools.length > 0, "CurveSwapper: ROUTE_NOT_SUPPORTED");

        uint256 amount = _amount;
        for (uint256 i = 0; i < route.pools.length; i++) {
            console.log("in loop");
            console.log("swapToken pools", route.pools[i]);
            /* amount = ICurve(route.pools[i]).exchange_underlying(
                route.indexes[i.mul(2)], // [0]
                route.indexes[i.mul(2).add(1)], // [1]
                amount,
                0
            ); */
            /* amount = ICurve(route.pools[i]).exchange_underlying(
                0, // [0]
                0, // [1]
                amount,
                0
            ); */
            console.log("swapToken amount", amount);

            // fork testing low level required
            (bool success, bytes memory result) = address(route.pools[i]).call(
                abi.encodeWithSignature(
                    "exchange_underlying(int128,int128,uint256,uint256)",
                    0, // [0]
                    0, // [1]
                    amount,
                    0
                )
            );

            console.log("swapToken lowlevel curvee", success);

            /* (bool success, bytes memory result) = address(addrOfA).delegatecall(abi.encodeWithSignature("a()")); */

            /* uint256 val =  abi.decode(result, (uint256)); */

            /* console.log("swapToken lowlevel curvee", val); */

        }
        console.log("swapToken 2");

        uint256 bal2 = IERC20(_to).balanceOf(address(this));

        console.log("swapToken bal2", bal2);


        /* require(amount >= _minAmountOut, "CurveSwapper: INVALID_SWAP_RESULT"); */
        IERC20(_to).safeTransfer(
            _beneficiary,
            IERC20(_to).balanceOf(address(this))
        );
    }

    function getAmountOutMin(address _tokenIn, address _tokenOut, uint256 _amountIn) external view override returns (uint256) {
        return 0;
    }

}
