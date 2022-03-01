//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;
import {PoolStorage} from '../pool/PoolStorage.sol';

interface IPool {

  function getAddressesProvider() external view returns (address);

  event DepositSavings(
      address user,
      address asset,
      /* address wrapped, */
      uint256 amount
  );

  function depositSavings(
      address account,
      address asset,
      uint256 amount
  ) external;

  event DepositCollateralAndBorrow(
      address _collateralAsset, //
      address _debtAsset, // wrapp to borrow
      address account, // on behalf of
      uint256 collateralAmount, // collateral amount ---> receive amount*ltv in debt
      uint256 borrowAmount
  );

  function depositCollateralAndBorrow(
      address _collateralAsset, //
      address _debtAsset, // wrapp to borrow
      address account, // on behalf of
      uint256 amount, // collateral amount ---> receive amount*ltv in debt
      bool useSavings
  ) external;

  event RepayAndWithdraw(
      address user,
      address collateralAsset,
      address debtAsset,
      uint256 amount
  );

  function repayAndWithdraw(
      address _collateralAsset,
      address _debtAsset,
      uint256 amount,
      bool sendToSavings
  ) external;

  event WithdrawSavings(
      address user,
      address asset,
      uint256 amount
  );

  function withdrawSavings(
      address account,
      address asset,
      uint256 amount,
      bool emergency
  ) external;

  /* event LiquidationCall(
      address _collateralAsset,
      address _debtAsset,
      uint256 repayAmount,
      uint256 receiverAmount
  );

  function liquidationCall(
      address borrower,
      address _debtAsset,
      address _collateralAsset,
      uint256 amount
  ) external; */

  function getPoolAssetData(address asset) external view returns (PoolStorage.PoolAsset memory);

  /* function getMinPartialLiquidationValueInEth(address asset) external view returns (uint256); */

  function updateTotalDepositsLendable(address asset, uint256 amountAdded, uint256 amountRemoved) external;

  event CollateralTokenInit(
      address asset,
      address wrapped
  );

  function initCollateralToken(
      address asset,
      address wrapped,
      address router,
      address exchangeRateData,
      uint256 routerMinSupplyRedeemAmount,
      uint256 routerMaxSupplyRedeemAmount,
      uint256 collateralInterestRateFactor,
      uint256 ctd, // collateral to debt
      bool isRoutable
  ) external;

  event SavingsTokenInit(
      address asset,
      address wrapped
  );

  function initSavingsToken(
      address asset,
      address wrapped,
      address router,
      address exchangeRateData,
      uint256 routerMinSupplyRedeemAmount,
      uint256 depositsSuppliedInterestRateFactor,
      bool isRoutable
  ) external;

  function initDebtToken(
      address asset,
      address debtWrappedAsset,
      uint256 debtInterestRateFactor,
      uint256 ltv
  ) external;

}
