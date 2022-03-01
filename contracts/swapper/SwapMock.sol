//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";



import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {WrappedAsset} from "./WrappedAsset.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";
import "hardhat/console.sol";

contract SwapMock is ISwapper {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  constructor() {}

  function swapToken(
      address _from,
      address _to,
      uint256 _amount,
      uint256 _minAmountOut,
      address _beneficiary
  ) external override {
      uint256 _fromDecimals = IERC20Metadata(_from).decimals();

      uint256 _toDecimals = IERC20Metadata(_to).decimals();

      IERC20(_from).safeTransferFrom(msg.sender, address(this), _amount);

      WrappedAsset(_from).burn(_amount, address(this));


      WrappedAsset(_to).mint(address(this), _amount.mul(10**_toDecimals).div(10**_fromDecimals));
      console.log("SwapMock swapToken mint");

      uint256 balance = IERC20(_to).balanceOf(address(this));
      console.log("SwapMock swapToken balance", balance);

      IERC20(_to).transfer(_beneficiary, balance);
      console.log("SwapMock end");

  }

  function getAmountOutMin(address _tokenIn, address _tokenOut, uint256 _amountIn) external view override returns (uint256) {
      uint256 _tokenInDecimals = IERC20Metadata(_tokenIn).decimals();
      uint256 _tokenOutDecimals = IERC20Metadata(_tokenOut).decimals();
      return _amountIn.mul(10**_tokenOutDecimals).div(10**_tokenInDecimals);

  }


}
