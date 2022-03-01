// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

import {IMockExchangeRateFeeder} from "./MockExchangeRateFeeder.sol";
import {SafeMath} from "./open-zeppelin/contracts/math/SafeMath.sol";
import {WrappedAssetV1} from "./WrappedAssetV1.sol";
import {IMockExchangeRateFeederGov} from "./MockExchangeRateFeeder.sol";


import "hardhat/console.sol";

interface IMockConversionPool {
    function deposit(uint256 _amount) external;

    /* function deposit(uint256 _amount, uint256 _minAmountOut) external; */

    function redeem(uint256 _amount) external;

    /* function redeem(uint256 _amount, uint256 _minAmountOut) external; */
}

contract MockConversionPool is IMockConversionPool {
  using SafeMath for uint256;


    // pool token settings
  WrappedAssetV1 public inputToken; // DAI / USDC / USDT
  WrappedAssetV1 public outputToken; // aDAI / aUSDC / aUSDT

  IMockExchangeRateFeeder public feeder;


  constructor(
      address _inputToken, // DAI
      address _outputToken, // aDAI
      address _exchangeRateFeeder
  ) {
      inputToken = WrappedAssetV1(_inputToken);
      outputToken = WrappedAssetV1(_outputToken);
      feeder = IMockExchangeRateFeeder(_exchangeRateFeeder);
  }


  function deposit(uint256 _amount) external override {

      inputToken.transferFrom(msg.sender, address(this), _amount);

      uint256 pER = feeder.exchangeRateOf(address(inputToken), true);

      outputToken.mint(msg.sender, _amount.mul(1e18).div(pER));
  }


  function redeem(uint256 _amount) external override {
      outputToken.transferFrom(msg.sender, address(this), _amount); // not how it really works

      // uint256 balanceHere = outputToken.balanceOf(address(this));


      outputToken.burn(_amount, msg.sender);

      uint256 pER = feeder.exchangeRateOf(address(inputToken), true);

      uint256 amountToSendBack = _amount.mul(pER).div(1e18);

      inputToken.mint(address(this), amountToSendBack);

      inputToken.transfer(msg.sender, amountToSendBack);
  }

  modifier _updateExchangeRate {
      address[] memory tokens = new address[](1);
      tokens[0] = address(inputToken);
      IMockExchangeRateFeederGov(address(feeder)).startUpdate(tokens);
      feeder.update(address(inputToken));
      IMockExchangeRateFeederGov(address(feeder)).stopUpdate(tokens);
      _;
  }


}
