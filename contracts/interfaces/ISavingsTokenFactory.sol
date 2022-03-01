//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface ISavingsTokenFactory {

  event SavingsTokenDeployed(
      address asset,
      address wrapped
  );

  function initSavings(
      address asset,
      // == savings
      uint256 depositsSuppliedInterestRateFactor,
      uint256 lendableExchangeRateFactor,
      // == router ==
      address routerAddress, // anchor
      address routerExchangeRateFeederAddress,
      uint256 routerMinSupplyRedeemAmount, // min amount router allows
      uint256 routerMaxSupplyRedeemAmount,
      uint256 routerMaxSupplyAllottedFactor, // for savings
      address _swapper // curvefi ust
  ) external;
}
