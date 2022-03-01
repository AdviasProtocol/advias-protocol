//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IDebtTokenFactory {

  event DebtTokenDeployed(
      address asset,
      address wrapped
  );

  function initDebtToken(
      address asset,
      uint256 debtInterestRateFactor,
      uint256 ltv
  ) external;

}
