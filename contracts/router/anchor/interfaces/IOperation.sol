// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


interface IOperation {

    // Data Structure
    enum Status {IDLE, RUNNING, STOPPED}
    enum Type {NEUTRAL, DEPOSIT, REDEEM}

    struct Info {
        Status status;
        Type typ;
        address operator;
        uint256 amount;
        address input;
        address output;
        address swapper;
        address swapDest;
    }

    // Interfaces

    function terraAddress() external view returns (bytes32);

    function getCurrentStatus() external view returns (Info memory);

    function initDepositStable(
        address _operator,
        uint256 _amount,
        address _swapper,
        address _swapDest,
        bool _autoFinish
    ) external;

    function initRedeemStable(
        address _operator,
        uint256 _amount,
        address _swapper,
        address _swapDest,
        bool _autoFinish
    ) external;

    function finish() external;

    function finish(uint256 _minAmountOut) external;

    function finishDepositStable() external;

    function finishRedeemStable() external;

    function halt() external;

    function recover() external;

    function emergencyWithdraw(address _token, address _to) external;

    function emergencyWithdraw(address payable _to) external;
}
