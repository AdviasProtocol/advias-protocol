//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import {ISwapper} from "../interfaces/ISwapper.sol";
import "hardhat/console.sol";

library TransferHelper {
    /// @notice Transfers tokens from the targeted address to the given destination
    /// @notice Errors with 'STF' if transfer fails
    /// @param token The contract address of the token to be transferred
    /// @param from The originating address from which the tokens will be transferred
    /// @param to The destination address of the transfer
    /// @param value The amount to be transferred
    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'STF');
    }

    /// @notice Transfers tokens from msg.sender to a recipient
    /// @dev Errors with ST if transfer fails
    /// @param token The contract address of the token which will be transferred
    /// @param to The recipient of the transfer
    /// @param value The value of the transfer
    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'ST');
    }

    /// @notice Approves the stipulated contract to spend the given allowance in the given token
    /// @dev Errors with 'SA' if transfer fails
    /// @param token The contract address of the token to be approved
    /// @param to The target of the approval
    /// @param value The amount of the given token the target will be allowed to spend
    function safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.approve.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'SA');
    }

    /// @notice Transfers ETH to the recipient address
    /// @dev Fails with `STE`
    /// @param to The destination of the transfer
    /// @param value The value to be transferred
    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'STE');
    }
}

interface IUniswapV3SwapCallback {
    /// @notice Called to `msg.sender` after executing a swap via IUniswapV3Pool#swap.
    /// @dev In the implementation you must pay the pool tokens owed for the swap.
    /// The caller of this method must be checked to be a UniswapV3Pool deployed by the canonical UniswapV3Factory.
    /// amount0Delta and amount1Delta can both be 0 if no tokens were swapped.
    /// @param amount0Delta The amount of token0 that was sent (negative) or must be received (positive) by the pool by
    /// the end of the swap. If positive, the callback must send that amount of token0 to the pool.
    /// @param amount1Delta The amount of token1 that was sent (negative) or must be received (positive) by the pool by
    /// the end of the swap. If positive, the callback must send that amount of token1 to the pool.
    /// @param data Any data passed through by the caller via the IUniswapV3PoolActions#swap call
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external;
}

interface ISwapRouter is IUniswapV3SwapCallback {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another along the specified path
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactInputParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);

    struct ExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps as little as possible of one token for `amountOut` of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactOutputSingleParams` in calldata
    /// @return amountIn The amount of the input token
    function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn);

    struct ExactOutputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
    }

    /// @notice Swaps as little as possible of one token for `amountOut` of another along the specified path (reversed)
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactOutputParams` in calldata
    /// @return amountIn The amount of the input token
    function exactOutput(ExactOutputParams calldata params) external payable returns (uint256 amountIn);
}

/**
 * @title UniswapV2Swapper
 * @author Advias
 * @title Main swapping contract for protocol with Uniswap
 */
contract UniswapV3Swapper is ISwapper, Ownable {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  ISwapRouter public immutable swapRouter;

  constructor(ISwapRouter _swapRouter) {
      swapRouter = _swapRouter; // uniswap
  }

  struct Route {
      bool active;
      uint24 fee;
  }

  mapping(address => mapping(address => Route)) private routes;

  function getRoute(address _from, address _to)
      public
      view
      returns (Route memory)
  {
      return routes[_from][_to];
  }


  function setRoute(
      address _from, // asset to swap from
      address _to, // asset to swap to
      uint24 _fee,
      address[] memory _tokens
  ) public onlyOwner {
      /* console.log("uniswapv3 setroute"); */
      require(
          _tokens.length == 2,
          "UniswapV3: INVALID_LENGTH"
      );
      Route storage route = routes[_from][_to];
      route.fee = _fee;
      route.active = true;

      for (uint256 i = 0; i < _tokens.length; i++) {
          if (IERC20(_tokens[i]).allowance(address(this), address(swapRouter)) == 0) {
              IERC20(_tokens[i]).safeApprove(address(swapRouter), type(uint256).max);
          }
      }
  }


  function swapToken(
      address _from, // swap from
      address _to, // swap to
      uint256 _amount,
      uint256 _minAmountOut,
      address _beneficiary // ignore
  ) public override {
      TransferHelper.safeTransferFrom(_from, msg.sender, address(this), _amount);

      if (IERC20(_from).allowance(address(this), address(swapRouter)) == 0) {
          TransferHelper.safeApprove(_from, address(swapRouter), _amount);
      }

      Route memory route = routes[_from][_to];
      require(route.active, "Error: Route not active.");

      ISwapRouter.ExactInputSingleParams memory params =
          ISwapRouter.ExactInputSingleParams({
              tokenIn: _from, // going to uniswap
              tokenOut: _to, // back from uniswap
              fee: route.fee,
              recipient: address(this),
              deadline: block.timestamp,
              amountIn: _amount,
              amountOutMinimum: 0,
              sqrtPriceLimitX96: 0
          });

      // The call to `exactInputSingle` executes the swap.
      uint256 amountOut = swapRouter.exactInputSingle(params);
      require(amountOut > 0, "Error: Amount back zero.");

      IERC20(_to).safeTransfer(
          _beneficiary,
          IERC20(_to).balanceOf(address(this))
      );
  }

  function getAmountOutMin(address _tokenIn, address _tokenOut, uint256 _amountIn) external view override returns (uint256) {
      return 0;
  }

}
