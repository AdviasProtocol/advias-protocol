//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface ILiquidationCaller {
  function liquidationCall(
      address borrower,
      address receiver,
      address[] memory debtAssets,
      uint256[] memory repayAmounts,
      address[] memory collateralAssets
  ) external;

}
