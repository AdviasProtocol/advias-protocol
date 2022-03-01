//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {PoolStorage} from '../pool/PoolStorage.sol';
import {ICollateralToken} from '../interfaces/ICollateralToken.sol';
import {IAvaToken} from '../interfaces/IAvaToken.sol';
import {IDebtToken} from '../interfaces/IDebtToken.sol';
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {WadRayMath} from './WadRayMath.sol';
import {IExchangeRateData} from '../interfaces/IExchangeRateData.sol';
import {IPriceConsumerV3} from '../oracles/IPriceConsumerV3.sol';

// import "hardhat/console.sol";

/**
 * @title ValidationLogic library
 * @author Advias
 * @dev Holds the protocols validation logic functions
 **/

library ValidationLogic {
    using SafeMath for uint256;
    using WadRayMath for uint256;

    function validateLiquidation(
          bool liquidateOnCtd,
          bool liquidateOnLtv,
          address[] memory debtAssets,
          uint256[] memory repayAmounts
    ) internal view {
        require(debtAssets.length == repayAmounts.length, "Error: Debt assets and repay amounts length must be equal");
        require(liquidateOnCtd == true || liquidateOnLtv == true, "Error: Position cannot be liquidated");
    }
}
