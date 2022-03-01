//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface ICollateralTokenFactory {

  event CollateralTokenDeployed(
      address asset,
      address wrapped
  );

  function initCollateralToken(
      address asset,
      address router,
      address exchangeRateData,
      uint256 routerMinSupplyRedeemAmount,
      uint256 routerMaxSupplyRedeemAmount,
      uint256 collateralInterestRateFactor,
      uint256 ctd,
      bool isRoutable,
      bool isYield
  ) external;

}
