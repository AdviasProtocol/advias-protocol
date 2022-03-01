//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {WadRayMath} from '../libraries/WadRayMath.sol';
import {IPoolAddressesProvider} from '../interfaces/IPoolAddressesProvider.sol';
import {PoolStorage} from './PoolStorage.sol';
import {General} from '../libraries/General.sol';

import {ValidationLogic} from '../libraries/ValidationLogic.sol';

import {IPool} from '../interfaces/IPool.sol';
import {IPoolAssetData} from '../interfaces/IPoolAssetData.sol';
import {ICollateralToken} from '../interfaces/ICollateralToken.sol';
import {IDebtToken} from '../interfaces/IDebtToken.sol';
import {ILiquidationCaller} from '../interfaces/ILiquidationCaller.sol';
import {IPriceConsumerV3} from '../oracles/IPriceConsumerV3.sol';
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PoolLogic} from '../libraries/PoolLogic.sol';

import "hardhat/console.sol";

contract LiquidationCaller is ILiquidationCaller, PoolStorage {
  using SafeMath for uint256;
  using WadRayMath for uint256;
  using SafeERC20 for IERC20;

  /**
   * @dev Max liquidation of debt if minPartialLiquidationValueInEth breached
   * - As a percentage in wad
   **/
  uint256 public _maxLiquidationFactor;

  /**
   * @dev Factor of debt can liquidate on ltv
   * - As a percentage in wad
   **/
  uint256 public partialLiquidationFactor;

  /**
   * @dev Min value of asset in 18 decimals required to not use _maxLiquidationFactor
   **/
  uint256 public minPartialLiquidationValueInEth;

  /**
   * @dev Factor of debt to liquidate if using CTD
   * - CTD liquidations use current CTD as the amount to send to liquidator
   **/
  uint256 public ctdLiquidationFactor;

  /**
   * @dev Bonus of collateral to give liquidator on ltv liquidations
   * - As a percentage in wad
   **/
  uint256 public liquidationBonusFactor;


  IPoolAddressesProvider public _addressesProvider;
  IPoolAssetData private _poolAssetData;
  IPool private _pool;

  modifier onlyPoolAdmin() {
      require(msg.sender == _addressesProvider.getPoolAdmin());
      _;
  }

  modifier onlyPool() {
      require(msg.sender == _addressesProvider.getPool());
      _;
  }

  constructor(address provider) {
      _addressesProvider = IPoolAddressesProvider(provider);
      _pool = IPool(_addressesProvider.getPool());
      _poolAssetData = IPoolAssetData(_addressesProvider.getPoolAssetData());
      _maxLiquidationFactor = 1e18; // 100%
      partialLiquidationFactor = 5e17; // 50%
      minPartialLiquidationValueInEth = 10000*(10**18); // 10,000
      ctdLiquidationFactor = 2e17; // 20%
  }

  function setMaxLiquidationFactor(uint256 _factor) external {
      require(_factor <= 1e18, "Error: Cannot be over 100%");
      _maxLiquidationFactor = _factor;
  }

  function setPartialLiquidationFactor(uint256 _factor) external {
      require(_factor <= 1e18, "Error: Cannot be over 100%");
      partialLiquidationFactor = _factor;
  }

  function setMinPartialLiquidationValueInEth(uint256 _value) external {
      minPartialLiquidationValueInEth = _value;
  }

  function setCtdLiquidationFactor(uint256 _factor) external {
      require(_factor <= 1e18, "Error: Cannot be over 100%");
      ctdLiquidationFactor = _factor;
  }

  struct liquidationCallParams{
      address borrower;
      address receiver;
      address[] debtAssets;
      uint256[] repayAmounts;
      address[] collateralAssets;
      uint256 liquidationFactor;
      uint256 liquidationBonusFactor;
      bool liquidateOnCtd;
      bool liquidateOnLtv;
  }

  /**
   * @dev Liquidates borrower position
   * @param borrower Borrow of debt
   * @param receiver Address to receive bonus
   * @param debtAssets Array of debt assets liquidator is repaying
   * @param repayAmounts Array of debt repay amounts
   * @param collateralAssets Array of collateral assets receiver is rewarded with in relation to repay amounts
   * All arrays must be in order
   **/
  function liquidationCall(
      address borrower,
      address receiver,
      address[] memory debtAssets,
      uint256[] memory repayAmounts,
      address[] memory collateralAssets
  ) external override onlyPool {
      liquidationCallParams memory params;
      params.borrower = borrower;
      params.receiver = receiver;
      params.debtAssets = debtAssets;
      params.repayAmounts = repayAmounts;
      params.collateralAssets = collateralAssets;

      console.log("liquidationCall start");

      (   ,
          uint256 totalDebtValueInEth,
          uint256 averageMaxCtd, , ,
          uint256 collateralHealth,
          uint256 debtHealth
      ) = General.getUserData(
          _poolAssetData.getPoolAssetsList(),
          params.borrower,
          _addressesProvider.getPriceOracle(),
          address(_poolAssetData)
      );

      /* ValidationLogic.confirmRepayAmounts(
        debtAssets,
        repayAmounts
      );
      */

      params.liquidateOnCtd = false;
      params.liquidateOnLtv = false;
      if (collateralHealth < 1e18) {
          params.liquidateOnCtd = true;
          params.liquidationFactor = ctdLiquidationFactor;
      } else if (debtHealth < 1e18) {
          params.liquidateOnLtv = true;
          params.liquidationFactor = partialLiquidationFactor;
      }

      if (totalDebtValueInEth <= minPartialLiquidationValueInEth) {
          params.liquidationFactor = _maxLiquidationFactor;
      }

      ValidationLogic.validateLiquidation(
          params.liquidateOnCtd,
          params.liquidateOnLtv,
          params.debtAssets,
          params.repayAmounts
      );

      if (params.liquidateOnCtd) {
        /* liquidationCallOnCtd(
            averageMaxCtd,
            params.liquidationFactor,
            params.borrower,
            params.receiver,
            params.debtAssets,
            params.repayAmounts,
            params.collateralAssets
        ); */
        address collateralAssetAvaAddress = _poolAssetData.getCollateralWrappedAsset(params.collateralAssets[0]);
        /* uint256 collateralAssetDecimals = _poolAssetData.getDecimals(params.collateralAssets[0]); */

        // amount of collateral balance of borrower
        /* uint256 collateralAmount = IERC20(collateralAssetAvaAddress).balanceOf(params.borrower); */

        /* uint256 collateralValueInEth = PoolLogic.getValueInEth(
            params.collateralAssets[0],
            collateralAssetDecimals,
            collateralAmount,
            _addressesProvider.getPriceOracle()
        );

        // the liquidator may choose a collateral asset that is lesser than
        // the debt asset value that can be paid off
        // this can create an abuse strategy by a borrower to lower debt and inrease collateral for yield
        // this is an unlikely scenerio by anyone liquidating

        // in order to not let the CTD ratio go higher than current
        // the total amount to liquiate 1:1 on debt needs to be maxed out
        // this stops abuse of self-liquidating to lower debt but keep collateral at a high yield
        // valueInEthMaxToLiquidate = collateral/averageCTD
        // valueInEthMaxToLiquidate * averageMaxCtd is the total receiver value
        console.log("liq 1");
        uint256 valueInEthMaxToLiquidate = collateralValueInEth.wadDiv(averageMaxCtd);
        console.log("liq 2"); */

        // 2
        // update and set repay amount if needed
        address debtAssetAvaAddress = _poolAssetData.getDebtWrappedAsset(params.debtAssets[0]);
        /* uint256 debtAssetDecimals = _poolAssetData.getDecimals(params.debtAssets[0]);
        uint256 debtAssetExchangeRate = _poolAssetData.getBorrowExchangeRate(params.debtAssets[0]); */

        // get max debt that can be repaid
        console.log("liq 3");

        uint256 maxDebtRepayAmount = IERC20(debtAssetAvaAddress).balanceOf(params.borrower).wadMul(params.liquidationFactor);
        console.log("liq 4 maxDebtRepayAmount", maxDebtRepayAmount);
        console.log("liq 4", params.repayAmounts[0]);

        liquidationCallOnCtdSingle(
            params.debtAssets[0],
            params.collateralAssets[0],
            averageMaxCtd,
            params.borrower,
            params.receiver,
            params.repayAmounts[0],
            maxDebtRepayAmount,
            /* valueInEthMaxToLiquidate, */
            collateralAssetAvaAddress,
            debtAssetAvaAddress
        );
      } else {
        liquidationCallOnLtv(
            params.borrower,
            params.receiver,
            params.debtAssets,
            params.repayAmounts,
            params.collateralAssets,
            params.liquidationBonusFactor
        );
      }

  }

  struct LiquidationCallOnCtdParams {
      uint256 averageMaxCtd;
      address borrower;
      address receiver;
      address[] debtAssets;
      uint256[] repayAmounts;
      address[] collateralAssets;
      uint256[] debtValuesInEth;
      uint256[] repayValuesInEth;
      uint256 totalRepayValueInEth;
  }

  /**
   * @dev Liquidates debt positions based on CTD and rewards collateral asset value to receiver plus available bonus
   * @param averageMaxCtd Overall average ctd ratio
   * @param liquidationFactor Overall average ctd ratio
   * @param borrower Borrower to repay debt for and liquidate from
   * @param receiver Address to transfer reward to
   * @param debtAssets Array of debt assets being repaid
   * @param repayAmounts Array of debt assets amounts being repaid
   * @param collateralAssets Array of collateral assets being liquidated


   * Step 1: Recalculate repayAmounts and adjust and turn into 18 dec
   * Step 2:
   **/
   function liquidationCallOnCtd(
       uint256 averageMaxCtd,
       uint256 liquidationFactor,
       address borrower,
       address receiver,
       address[] memory debtAssets,
       uint256[] memory repayAmounts,
       address[] memory collateralAssets
   ) private returns (bool) {
       console.log(" start of ctd liquidation ");
       LiquidationCallOnCtdParams memory params;

       params.averageMaxCtd = averageMaxCtd;
       params.borrower = borrower;
       params.receiver = receiver;
       params.debtAssets = debtAssets;
       params.repayAmounts = repayAmounts;
       params.collateralAssets = collateralAssets;

       params.debtValuesInEth = new uint256[](params.repayAmounts.length);
       params.repayValuesInEth = new uint256[](params.repayAmounts.length);


   }
  /* function liquidationCallOnCtd(
      uint256 averageMaxCtd,
      uint256 liquidationFactor,
      address borrower,
      address receiver,
      address[] memory debtAssets,
      uint256[] memory repayAmounts,
      address[] memory collateralAssets
  ) private returns (bool) {
      console.log(" start of ctd liquidation ");
      LiquidationCallOnCtdParams memory params;

      params.averageMaxCtd = averageMaxCtd;
      params.borrower = borrower;
      params.receiver = receiver;
      params.debtAssets = debtAssets;
      params.repayAmounts = repayAmounts;
      params.collateralAssets = collateralAssets;

      params.debtValuesInEth = new uint256[](params.repayAmounts.length);
      params.repayValuesInEth = new uint256[](params.repayAmounts.length);

      // loop through each repayAmount and get amounts valued in Eth decimals
      // update repayAmounts if repayAmount is greater than the max on that asset
      // example: if receiver enters 1000 but there is 750 of total debt*factor, the liquidate amount will reduce tto 750
      for (uint256 i = 0; i < params.repayAmounts.length; i++) {
          console.log(" start of ctd liquidation params.repayAmounts", params.repayAmounts[i]);
          console.log(" start of ctd liquidation i", i);

          address debtAssetAvaAddress = _poolAssetData.getDebtWrappedAsset(params.debtAssets[i]);
          uint256 debtAssetDecimals = _poolAssetData.getDecimals(params.debtAssets[i]);

          console.log("1 liquidationFactor", liquidationFactor);
          // max debt amount that can be repaid
          uint256 debtAmount = IERC20(debtAssetAvaAddress).balanceOf(params.borrower).wadMul(liquidationFactor);
          console.log(" start of ctd debtAmount", debtAmount);

          // max debt value that can be repaid
          params.debtValuesInEth[i] = PoolLogic.getValueInEth(
              params.debtAssets[i],
              debtAssetDecimals,
              debtAmount,
              _addressesProvider.getPriceOracle()
          );

          params.repayValuesInEth[i] += PoolLogic.getValueInEth(
              params.debtAssets[i],
              debtAssetDecimals,
              params.repayAmounts[i],
              _addressesProvider.getPriceOracle()
          );
          console.log(" params.repayValuesInEth i", params.repayValuesInEth[i]);

          // update repay values if greater than max available for liq
          if (params.repayValuesInEth[i] > params.debtValuesInEth[i]) {
              params.repayValuesInEth[i] = params.debtValuesInEth[i];
          }

          params.totalRepayValueInEth += params.repayValuesInEth[i];

      }
      console.log(" liquidationCallOnCtd params.averageMaxCtd ", params.averageMaxCtd);
      console.log(" liquidationCallOnCtd params.totalRepayValueInEth ", params.totalRepayValueInEth);

      uint256 totalRepayValueInEthPlusBonus = params.totalRepayValueInEth.wadMul(params.averageMaxCtd);
      console.log(" liquidationCallOnCtd totalRepayValueInEthPlusBonus  ", totalRepayValueInEthPlusBonus);

      uint256 remainingValueInEthToLiquidate = totalRepayValueInEthPlusBonus;
      console.log(" liquidationCallOnCtd remainingValueInEthToLiquidate ", remainingValueInEthToLiquidate);

      // liquidate collateral up to totalRepayValueInEthPlusBonus
      for (uint256 i = 0; i < params.collateralAssets.length; i++) {
          bool isStable = _poolAssetData.getIsStable(params.collateralAssets[i]);
          if (
            remainingValueInEthToLiquidate == 0 ||
            !isStable
          ) {
              continue;
          }

          address collateralAssetAvaAddress = _poolAssetData.getCollateralWrappedAsset(params.collateralAssets[i]);
          uint256 collateralAssetDecimals = _poolAssetData.getDecimals(params.collateralAssets[i]);

          uint256 collateralAmount = IERC20(collateralAssetAvaAddress).balanceOf(params.borrower);
          console.log(" liquidationCallOnCtd collateralAmount ", collateralAmount);

          uint256 collateralValueInEth = PoolLogic.getValueInEth(
              params.collateralAssets[i],
              collateralAssetDecimals,
              collateralAmount,
              _addressesProvider.getPriceOracle()
          );
          console.log(" liquidationCallOnCtd collateralValueInEth ", collateralValueInEth);

          // check collateral is at least 1:1 on repay value
          //uint256 principalRepay = params.repayValuesInEth[i];
          //if (collateralValueInEth < principalRepay) {
          //    principalRepay = collateralValueInEth;
          //}

          // goal amount to liquidate and burn in this iteration
          // * should always be equal or less than remainingValueInEthToLiquidate
          uint256 valueInEthToLiquidatePlusBonus = params.repayValuesInEth[i].wadMul(params.averageMaxCtd);

          // uint256 valueInEthToLiquidate = remainingValueInEthToLiquidate;
          // if borrower balance is less than reward goal, use borrower balance
          // if 1000 > 1500
          if (collateralValueInEth < valueInEthToLiquidatePlusBonus) {
              valueInEthToLiquidatePlusBonus = collateralValueInEth;
              remainingValueInEthToLiquidate -= collateralValueInEth
          } else {
              remainingValueInEthToLiquidate -= valueInEthToLiquidatePlusBonus;
          }




          //if (valueInEthToLiquidate < remainingValueInEthToLiquidate) {
          //    valueInEthToLiquidate = collateralValueInEth;
          //    remainingValueInEthToLiquidate -= collateralValueInEth
          //} else {
          //    remainingValueInEthToLiquidate -= valueInEthToLiquidate;
          //}



          uint256 collateralBurnAmount = PoolLogic.getAmountFromValueInEth(
              params.collateralAssets[i],
              collateralAssetDecimals,
              valueInEthToLiquidatePlusBonus,
              _addressesProvider.getPriceOracle()
          );
          console.log(" liquidationCallOnCtd collateralBurnAmount ", collateralBurnAmount);

          // burn collateral
          // send to receiver
          uint256 collateralExchangeRate = _poolAssetData.getCollateralExchangeRate(params.collateralAssets[i]);
          ICollateralToken(collateralAssetAvaAddress).burnAndRedeem(
              params.borrower,
              params.receiver,
              address(0),
              collateralBurnAmount,
              collateralExchangeRate
          );

          // safe from conditional
          // remainingValueInEthToLiquidate -= valueInEthToLiquidate;

      }
      console.log(" liquidationCallOnCtd totalRepayValueInEthPlusBonus ", totalRepayValueInEthPlusBonus);
      console.log(" liquidationCallOnCtd remainingValueInEthToLiquidate", remainingValueInEthToLiquidate);

      // if false, nothing was liquidated
      require(totalRepayValueInEthPlusBonus != remainingValueInEthToLiquidate, "Error: Select collateral assets cannot be liquidated");
      console.log(" liquidationCallOnCtd after require");

      // repayUnmetValueInEth The amount to remove from safeTransferFrom and debt for liquidtor to repayy
      // if there are multiple debt and collateral positions but liquidator
      // includes collateral positions too few in value to meet liquidation amount
      // then remove the difference from the repay transfer in
      uint256 repayUnmetValueInEth;
      if (remainingValueInEthToLiquidate < totalRepayValueInEthPlusBonus) {
          repayUnmetValueInEth = totalRepayValueInEthPlusBonus.sub(remainingValueInEthToLiquidate);
      }
      console.log(" repayUnmetValueInEth", repayUnmetValueInEth);


      uint256 remainingRepayUnmetValueInEth = repayUnmetValueInEth;
      for (uint256 i = 0; i < params.repayValuesInEth.length; i++) {
          console.log(" in params.repayValuesInEth.length 1");

          if (remainingRepayUnmetValueInEth > repayUnmetValueInEth) {
              remainingRepayUnmetValueInEth -= params.repayValuesInEth[i];
              continue; // /////// skip
          }
          console.log(" in params.repayValuesInEth.length 2");

          uint256 repayValueInEthToTransfer = params.repayValuesInEth[i].sub(remainingRepayUnmetValueInEth);
          uint256 debtAssetDecimals = _poolAssetData.getDecimals(params.debtAssets[i]);
          uint256 exchangeRate = _poolAssetData.getBorrowExchangeRate(params.debtAssets[i]);

          uint256 repayAmount = PoolLogic.getAmountFromValueInEth(
              params.debtAssets[i],
              debtAssetDecimals,
              repayValueInEthToTransfer,
              _addressesProvider.getPriceOracle()
          );

          address debtAssetAvaAddress = _poolAssetData.getDebtWrappedAsset(params.debtAssets[i]);
          console.log(" start of ctd liquidation repayAmount", repayAmount);

          IDebtToken(debtAssetAvaAddress).burn(params.borrower, repayAmount, exchangeRate);

          IERC20(params.debtAssets[i]).safeTransferFrom(params.receiver, debtAssetAvaAddress, repayAmount);
      }

  } */

  struct LiquidationCallOnCtdSingleParams {
      uint256 averageMaxCtd;
      uint256 liquidationFactor;
      address borrower;
      address receiver;
      address debtAsset;
      uint256 repayAmount;
      address collateralAsset;
      uint256 debtValuesInEth;
      uint256 repayValuesInEth;
      uint256 totalRepayValueInEth;
      address priceOracle;
  }

  // check if max liquidation will put borrower avg ctd over avg ctd
  // 1 Get max collateral liquidation amount not including bonus reward
  // 2 Update repayAmount to reflect max collateral and max debt
  // 3 Burn borrower debt
  // 4 Burn collateral and send to receiver
  // 5 Transfer in repay amount in debt asset
  /* function liquidationCallOnCtdSingle(
      uint256 averageMaxCtd,
      uint256 liquidationFactor,
      address borrower,
      address receiver,
      address debtAsset,
      uint256 repayAmount,
      address collateralAsset
  ) private returns (bool) {
      LiquidationCallOnCtdSingleParams memory params;

      params.averageMaxCtd = averageMaxCtd;
      params.liquidationFactor = liquidationFactor;
      params.borrower = borrower;
      params.receiver = receiver;
      params.debtAsset = debtAsset;
      params.repayAmount = repayAmount;
      params.collateralAsset = collateralAsset;
      params.priceOracle = _addressesProvider.getPriceOracle();
      // 1
      // get max liquidation amount
      // this is a ctd liq so the amount to liquidate for repay must always be lower than collateral total
      address collateralAssetAvaAddress = _poolAssetData.getCollateralWrappedAsset(params.collateralAsset);
      uint256 collateralAssetDecimals = _poolAssetData.getDecimals(params.collateralAsset);

      // amount of collateral balance of borrower
      uint256 collateralAmount = IERC20(collateralAssetAvaAddress).balanceOf(params.borrower);


      uint256 collateralValueInEth = PoolLogic.getValueInEth(
          params.collateralAsset,
          collateralAssetDecimals,
          collateralAmount,
          params.priceOracle
      );

      // the liquidator may choose a collateral asset that is lesser than
      // the debt asset value that can be paid off
      // this can create an abuse strategy by a borrower to lower debt and inrease collateral for yield
      // this is an unlikely scenerio by anyone liquidating

      // in order to not let the CTD ratio go higher than current
      // the total amount to liquiate 1:1 on debt needs to be maxed out
      // this stops abuse of self-liquidating to lower debt but keep collateral at a high yield
      // valueInEthMaxToLiquidate = collateral/averageCTD
      // valueInEthMaxToLiquidate * averageMaxCtd is the total receiver value
      uint256 valueInEthMaxToLiquidate = collateralValueInEth.wadDiv(params.averageMaxCtd);


      // 2
      // update and set repay amount if needed
      address debtAssetAvaAddress = _poolAssetData.getDebtWrappedAsset(params.debtAsset);
      uint256 debtAssetDecimals = _poolAssetData.getDecimals(params.debtAsset);
      uint256 debtAssetExchangeRate = _poolAssetData.getBorrowExchangeRate(params.debtAsset);

      // get max debt that can be repaid
      uint256 maxDebtRepayAmount = IERC20(debtAssetAvaAddress).balanceOf(params.borrower).wadMul(params.liquidationFactor);

      if (params.repayAmount > maxDebtRepayAmount) {
          params.repayAmount = maxDebtRepayAmount;
      }

      uint256 repayValueInEth = PoolLogic.getValueInEth(
          params.debtAsset,
          debtAssetDecimals,
          params.repayAmount,
          params.priceOracle
      );

      if (repayValueInEth > valueInEthMaxToLiquidate) {
          repayValueInEth = valueInEthMaxToLiquidate;
      }

      uint256 repayAmount = PoolLogic.getAmountFromValueInEth(
          params.debtAsset,
          debtAssetDecimals,
          repayValueInEth,
          params.priceOracle
      );

      // burn borrower debt
      IDebtToken(debtAssetAvaAddress).burn(params.borrower, repayAmount, debtAssetExchangeRate);

      uint256 collateralBurnAmount = PoolLogic.getAmountFromValueInEth(
          params.collateralAsset,
          collateralAssetDecimals,
          repayValueInEth.wadMul(params.averageMaxCtd),
          params.priceOracle
      );
      console.log(" liquidationCallOnCtd collateralBurnAmount ", collateralBurnAmount);

      // burn collateral
      // send to receiver
      uint256 collateralExchangeRate = _poolAssetData.getCollateralExchangeRate(params.collateralAsset);
      ICollateralToken(collateralAssetAvaAddress).burnAndRedeem(
          params.borrower,
          params.receiver,
          address(0), // _toAsset --- 0 defauls to underlying
          collateralBurnAmount,
          collateralExchangeRate
      );

      IERC20(params.debtAsset).safeTransferFrom(msg.sender, debtAssetAvaAddress, repayAmount);




  } */

  function liquidationCallOnCtdSingle(
      address debtAsset,
      address collateralAsset,
      uint256 averageMaxCtd,
      address borrower,
      address receiver,
      uint256 repayAmount,
      uint256 maxDebtRepayAmount,
      /* uint256 valueInEthMaxToLiquidate, */
      address collateralAssetAvaAddress,
      address debtAssetAvaAddress
  ) private returns (bool) {
      LiquidationCallOnCtdSingleParams memory params;

      params.averageMaxCtd = averageMaxCtd;
      /* params.liquidationFactor = liquidationFactor; */
      params.borrower = borrower;
      params.receiver = receiver;
      params.debtAsset = debtAsset;
      params.repayAmount = repayAmount;
      params.collateralAsset = collateralAsset;
      params.priceOracle = _addressesProvider.getPriceOracle();
      // 1
      // get max liquidation amount
      // this is a ctd liq so the amount to liquidate for repay must always be lower than collateral total
      /* address collateralAssetAvaAddress = _poolAssetData.getCollateralWrappedAsset(params.collateralAsset);
      uint256 collateralAssetDecimals = _poolAssetData.getDecimals(params.collateralAsset);

      // amount of collateral balance of borrower
      uint256 collateralAmount = IERC20(collateralAssetAvaAddress).balanceOf(params.borrower);


      uint256 collateralValueInEth = PoolLogic.getValueInEth(
          params.collateralAsset,
          collateralAssetDecimals,
          collateralAmount,
          params.priceOracle
      ); */

      // the liquidator may choose a collateral asset that is lesser than
      // the debt asset value that can be paid off
      // this can create an abuse strategy by a borrower to lower debt and inrease collateral for yield
      // this is an unlikely scenerio by anyone liquidating

      // in order to not let the CTD ratio go higher than current
      // the total amount to liquiate 1:1 on debt needs to be maxed out
      // this stops abuse of self-liquidating to lower debt but keep collateral at a high yield
      // valueInEthMaxToLiquidate = collateral/averageCTD
      // valueInEthMaxToLiquidate * averageMaxCtd is the total receiver value
      /* uint256 valueInEthMaxToLiquidate = collateralValueInEth.wadDiv(params.averageMaxCtd); */


      // 2
      // update and set repay amount if needed
      /* address debtAssetAvaAddress = _poolAssetData.getDebtWrappedAsset(params.debtAsset);
      uint256 debtAssetDecimals = _poolAssetData.getDecimals(params.debtAsset);
      uint256 debtAssetExchangeRate = _poolAssetData.getBorrowExchangeRate(params.debtAsset);

      // get max debt that can be repaid
      uint256 maxDebtRepayAmount = IERC20(debtAssetAvaAddress).balanceOf(params.borrower).wadMul(params.liquidationFactor); */
      uint256 collateralAmount = IERC20(collateralAssetAvaAddress).balanceOf(params.borrower);
      console.log(" liquidationCallOnCtdSingle collateralAmount ", collateralAmount);

      uint256 collateralAssetDecimals = _poolAssetData.getDecimals(params.collateralAsset);
      console.log(" liquidationCallOnCtdSingle collateralAssetDecimals ", collateralAssetDecimals);

      uint256 collateralValueInEth = PoolLogic.getValueInEth(
          params.collateralAsset,
          collateralAssetDecimals,
          collateralAmount,
          _addressesProvider.getPriceOracle()
      );
      console.log(" liquidationCallOnCtdSingle collateralValueInEth ", collateralValueInEth);

      // the liquidator may choose a collateral asset that is lesser than
      // the debt asset value that can be paid off
      // this can create an abuse strategy by a borrower to lower debt and inrease collateral for yield
      // this is an unlikely scenerio by anyone liquidating

      // in order to not let the CTD ratio go higher than current
      // the total amount to liquiate 1:1 on debt needs to be maxed out
      // this stops abuse of self-liquidating to lower debt but keep collateral at a high yield
      // valueInEthMaxToLiquidate = collateral/averageCTD
      // valueInEthMaxToLiquidate * averageMaxCtd is the total receiver value
      console.log("liq 1");
      uint256 valueInEthMaxToLiquidate = collateralValueInEth.wadDiv(averageMaxCtd);
      console.log("liq 2 valueInEthMaxToLiquidate" , valueInEthMaxToLiquidate);

      uint256 debtAssetDecimals = _poolAssetData.getDecimals(params.debtAsset);
      uint256 debtAssetExchangeRate = _poolAssetData.getBorrowExchangeRate(params.debtAsset);
      console.log(" liquidationCallOnCtdSingle start ");
      console.log("liq params.repayAmount 1", params.repayAmount);

      if (params.repayAmount > maxDebtRepayAmount) {
          params.repayAmount = maxDebtRepayAmount;
      }
      console.log("liq params.repayAmount  ", params.repayAmount);

      uint256 repayValueInEth = PoolLogic.getValueInEth(
          params.debtAsset,
          debtAssetDecimals,
          params.repayAmount,
          params.priceOracle
      );
      console.log(" liquidationCallOnCtdSingle after repayValueInEth ", repayValueInEth);

      if (repayValueInEth > valueInEthMaxToLiquidate) {
          repayValueInEth = valueInEthMaxToLiquidate;
      }

      uint256 finalRepayAmount = PoolLogic.getAmountFromValueInEth(
          params.debtAsset,
          debtAssetDecimals,
          repayValueInEth,
          params.priceOracle
      );
      console.log(" liquidationCallOnCtdSingle after finalRepayAmount ", finalRepayAmount);

      // burn borrower debt
      IDebtToken(debtAssetAvaAddress).burn(params.borrower, finalRepayAmount, debtAssetExchangeRate);

      /* uint256 collateralAssetDecimals = _poolAssetData.getDecimals(params.collateralAsset); */

      uint256 collateralBurnAmount = PoolLogic.getAmountFromValueInEth(
          params.collateralAsset,
          collateralAssetDecimals,
          repayValueInEth.wadMul(params.averageMaxCtd),
          params.priceOracle
      );
      console.log(" liquidationCallOnCtd collateralBurnAmount ", collateralBurnAmount);

      // burn collateral
      // send to receiver
      uint256 collateralExchangeRate = _poolAssetData.getCollateralExchangeRate(params.collateralAsset);
      ICollateralToken(collateralAssetAvaAddress).burnAndRedeem(
          params.borrower,
          params.receiver,
          address(0), // _toAsset --- 0 defauls to underlying
          collateralBurnAmount,
          collateralExchangeRate
      );
      console.log(" liquidationCallOnCtd after burnAndRedeem ");
      console.log(" liquidationCallOnCtd b safeTransferFrom ", finalRepayAmount);
      console.log(" liquidationCallOnCtd b msg.sender ", msg.sender);
      console.log(" liquidationCallOnCtd b allowance ", IERC20(params.debtAsset).allowance(msg.sender, address(this)));
      console.log(" liquidationCallOnCtd b address(this) ", address(this));
      console.log(" liquidationCallOnCtd b params.debtAsset ", params.debtAsset);

      IERC20(params.debtAsset).safeTransferFrom(params.receiver, debtAssetAvaAddress, finalRepayAmount);




  }


  /**
   * @dev Liquidates debt positions based on LTV and rewards collateral asset value to receiver plus available bonus
   * @param borrower Borrower to repay debt for and liquidate from
   * @param receiver Address to transfer reward to
   * @param debtAssets Array of debt assets being repaid
   * @param repayAmounts Array of debt assets amounts being repaid
   * @param collateralAssets Array of collateral assets being liquidated
   * @param liquidationBonusFactor Bonus percentage of collateral to send to receiver
   *
   * liquidationCallOnLtv is a function here for scalability purposes and will likely not be in use
   **/
  function liquidationCallOnLtv(
      address borrower,
      address receiver,
      address[] memory debtAssets,
      uint256[] memory repayAmounts,
      address[] memory collateralAssets,
      uint256 liquidationBonusFactor
  ) private returns (bool) {
      console.log(" start of ltv liquidation ");
      LiquidationCallOnCtdParams memory params;

      params.borrower = borrower;
      params.receiver = receiver;
      params.debtAssets = debtAssets;
      params.repayAmounts = repayAmounts;
      params.collateralAssets = collateralAssets;

      params.debtValuesInEth = new uint256[](params.repayAmounts.length);
      params.repayValuesInEth = new uint256[](params.repayAmounts.length);

      for (uint256 i = 0; i < params.repayAmounts.length; i++) {
          console.log(" start of ctd liquidation params.repayAmounts", params.repayAmounts[i]);
          console.log(" start of ctd liquidation i", i);

          address debtAssetAvaAddress = _poolAssetData.getDebtWrappedAsset(params.debtAssets[i]);
          uint256 debtAssetDecimals = _poolAssetData.getDecimals(params.debtAssets[i]);

          uint256 debtAmount = IERC20(debtAssetAvaAddress).balanceOf(params.borrower);

          params.debtValuesInEth[i] = PoolLogic.getValueInEth(
              params.debtAssets[i],
              debtAssetDecimals,
              debtAmount,
              _addressesProvider.getPriceOracle()
          );

          params.repayValuesInEth[i] += PoolLogic.getValueInEth(
              params.debtAssets[i],
              debtAssetDecimals,
              params.repayAmounts[i],
              _addressesProvider.getPriceOracle()
          );

          if (params.repayValuesInEth[i] > params.debtValuesInEth[i]) {
              params.repayValuesInEth[i] = params.debtValuesInEth[i];
          }

          params.totalRepayValueInEth += params.repayValuesInEth[i];

      }

      uint256 totalRepayValueInEthPlusBonus = params.totalRepayValueInEth.wadMul(liquidationBonusFactor);

      uint256 remainingValueInEthToLiquidate = totalRepayValueInEthPlusBonus;

      for (uint256 i = 0; i < params.collateralAssets.length; i++) {
          // only liquidate on ltv on non-stable asset
          // stable assets split between underlying asset an aust
          // UST is the only stable collateral asset
          //
          bool isStable = _poolAssetData.getIsStable(params.collateralAssets[i]);
          if (
            remainingValueInEthToLiquidate == 0 ||
            isStable
          ) {
              continue;
          }

          address collateralAssetAvaAddress = _poolAssetData.getCollateralWrappedAsset(params.collateralAssets[i]);
          uint256 collateralAssetDecimals = _poolAssetData.getDecimals(params.collateralAssets[i]);

          uint256 collateralAmount = IERC20(collateralAssetAvaAddress).balanceOf(params.borrower);

          uint256 collateralValueInEth = PoolLogic.getValueInEth(
              params.collateralAssets[i],
              collateralAssetDecimals,
              collateralAmount,
              _addressesProvider.getPriceOracle()
          );

          uint256 valueInEthToLiquidate = remainingValueInEthToLiquidate;
          if (collateralValueInEth < remainingValueInEthToLiquidate) {
              valueInEthToLiquidate = collateralValueInEth;
          }

          uint256 collateralBurnAmount = PoolLogic.getAmountFromValueInEth(
              params.collateralAssets[i],
              collateralAssetDecimals,
              valueInEthToLiquidate,
              _addressesProvider.getPriceOracle()
          );

          uint256 collateralExchangeRate = _poolAssetData.getCollateralExchangeRate(params.collateralAssets[i]);
          ICollateralToken(collateralAssetAvaAddress).burnAndRedeem(
              params.borrower,
              params.receiver,
              address(0),
              collateralBurnAmount,
              collateralExchangeRate
          );

          remainingValueInEthToLiquidate -= valueInEthToLiquidate;

      }

      require(totalRepayValueInEthPlusBonus != remainingValueInEthToLiquidate, "Error: Select collateral assets cannot be liquidated");

      // repayUnmetValueInEth The amount to remove from safeTransferFrom
      // if there are multiple debt and collateral positions but liquidator
      // includes collateral positions too few in value to meet liquidation amount
      // theen remove the difference from the repay transfer in
      uint256 repayUnmetValueInEth;
      if (remainingValueInEthToLiquidate < totalRepayValueInEthPlusBonus) {
          repayUnmetValueInEth = totalRepayValueInEthPlusBonus.sub(remainingValueInEthToLiquidate);
      }


      uint256 remainingRepayUnmetValueInEth = repayUnmetValueInEth;
      for (uint256 i = 0; i < params.repayValuesInEth.length; i++) {
          if (remainingRepayUnmetValueInEth > params.repayValuesInEth[i]) {
              remainingRepayUnmetValueInEth -= params.repayValuesInEth[i];
              continue; // /////// skip
          }
          uint256 repayValueInEthToTransfer = params.repayValuesInEth[i].sub(remainingRepayUnmetValueInEth);
          uint256 debtAssetDecimals = _poolAssetData.getDecimals(params.debtAssets[i]);
          uint256 exchangeRate = _poolAssetData.getBorrowExchangeRate(params.debtAssets[i]);

          uint256 repayAmount = PoolLogic.getAmountFromValueInEth(
              params.debtAssets[i],
              debtAssetDecimals,
              repayValueInEthToTransfer,
              _addressesProvider.getPriceOracle()
          );

          address debtAssetAvaAddress = _poolAssetData.getDebtWrappedAsset(params.debtAssets[i]);
          console.log(" start of ctd liquidation repayAmount", repayAmount);

          IDebtToken(debtAssetAvaAddress).burn(params.borrower, repayAmount, exchangeRate);

          IERC20(params.debtAssets[i]).safeTransferFrom(params.receiver, debtAssetAvaAddress, repayAmount);
      }




  }

}
