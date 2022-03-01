// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOperation} from "./IOperation.sol";

interface IRouterV2 {
    // ======================= common ======================= //

    function init(
        IOperation.Type _type,
        address _operator,
        uint256 _amount,
        address _swapper,
        address _swapDest,
        bool _autoFinish
    ) external returns (address);

    function finish(address _operation) external;

    // ======================= deposit stable ======================= //

    function depositStable(uint256 _amount) external returns (address);

    function depositStable(address _operator, uint256 _amount)
        external
        returns (address);

    function initDepositStable(uint256 _amount) external returns (address);

    function finishDepositStable(address _operation) external;

    // ======================= redeem stable ======================= //

    function redeemStable(uint256 _amount) external returns (address);

    function redeemStable(address _operator, uint256 _amount)
        external
        returns (address);

    function initRedeemStable(uint256 _amount) external returns (address);

    function finishRedeemStable(address _operation) external;

    function wUST() external returns (address);

    function aUST() external returns (address);
}

interface IConversionRouterV2 is IRouterV2 {
    // ======================= deposit stable ======================= //

    function depositStable(
        address _operator,
        uint256 _amount,
        address _swapper,
        address _swapDest
    ) external returns (address);

    function initDepositStable(
        uint256 _amount,
        address _swapper,
        address _swapDest
    ) external returns (address);

    // ======================= redeem stable ======================= //

    function redeemStable(
        address _operator,
        uint256 _amount,
        address _swapper,
        address _swapDest
    ) external returns (address);

    function initRedeemStable(
        uint256 _amount,
        address _swapper,
        address _swapDest
    ) external returns (address);
}
