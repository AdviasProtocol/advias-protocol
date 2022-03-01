// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;

import {SafeMath} from "./open-zeppelin/contracts/math/SafeMath.sol";
import {IERC20} from "./open-zeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "./open-zeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Context} from "./open-zeppelin/contracts/utils/Context.sol";
import {IMockOperation} from "./MockOperation.sol";
import "hardhat/console.sol";

interface IMockRouter {
    // ======================= common ======================= //

    /* function init(
        IMockOperation.Type _type,
        address _operator,
        uint256 _amount,
        address _swapper,
        address _swapDest,
        bool _autoFinish
    ) external; */

    /* function finish(address _operation) external; */

    // ======================= deposit stable ======================= //

    /* function depositStable(uint256 _amount) external; */

    /* function depositStable(address _operator, uint256 _amount) external; */
    function depositStable(address _operator, uint256 _amount)
        external
        returns (address);

    /* function initDepositStable(uint256 _amount) external; */

    /* function finishDepositStable(address _operation) external; */

    // ======================= redeem stable ======================= //

    /* function redeemStable(uint256 _amount) external; */

    /* function redeemStable(address _operator, uint256 _amount) external; */
    function redeemStable(address _operator, uint256 _amount)
        external
        returns (address);


    /* function initRedeemStable(uint256 _amount) external; */

    /* function finishRedeemStable(address _operation) external; */

    /* function depositStable(
        address _operator,
        uint256 _amount,
        address _swapper,
        address _swapDest
    ) external returns (address); */

    /* function initDepositStable(
        uint256 _amount,
        address _swapper,
        address _swapDest
    ) external returns (address); */

    // ======================= redeem stable ======================= //

    function redeemStable(
        address _operator,
        uint256 _amount,
        address _swapper,
        address _swapDest
    ) external returns (address);

    /* function initRedeemStable(
        uint256 _amount,
        address _swapper,
        address _swapDest
    ) external returns (address); */

}

contract MockRouter is IMockRouter, Context {

  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  // operation
  /* address public optStore; */
  /* uint256 public optStdId; */
  /* address public optFactory; */

  // constant
  address public wUST;
  address public aUST;
  address public _operation;

  // flags
  bool public isDepositAllowed = true;
  bool public isRedemptionAllowed = true;

  /* function initialize(
      address _wUST,
      address _aUST
  ) public initializer {
      wUST = _wUST;
      aUST = _aUST;
      setOwner(msg.sender);
  } */

  constructor(
      address _wUST,
      address _aUST,
      address operation_
  ) {
      wUST = _wUST;
      aUST = _aUST;
      _operation = operation_;
      /* setOwner(msg.sender); */
  }


  function _init(
      IMockOperation.Type _typ,
      address _operator,
      uint256 _amount,
      address _swapper,
      address _swapDest,
      bool _autoFinish
  ) internal returns (address) {
      console.log("Mock MockRouter _init start");
      /* IMockOperationStore store = IMockOperationStore(optStore);
      if (store.getAvailableOperation() == address(0x0)) {
          address instance = IMockOperationFactory(optFactory).build(optStdId);
          store.allocate(instance);
      }
      IMockOperation operation = IMockOperation(store.init(_autoFinish)); */

      IMockOperation operation = IMockOperation(_operation);

      // check allowance
      if (IERC20(wUST).allowance(address(this), address(operation)) == 0) {
          IERC20(wUST).safeApprove(address(operation), type(uint256).max);
          IERC20(aUST).safeApprove(address(operation), type(uint256).max);
      }

      if (_typ == IMockOperation.Type.DEPOSIT) {
          console.log("Mock MockRouter IMockOperation.Type.DEPOSIT wUST", wUST);
          console.log("Mock MockRouter IMockOperation.Type.DEPOSIT _amount", _amount);

          console.log("Mock MockRouter IMockOperation.Type.DEPOSIT _msgSender", _msgSender());
          IERC20(wUST).safeTransferFrom(_msgSender(), address(this), _amount);
          console.log("Mock MockRouter IMockOperation.Type.DEPOSIT");
          uint256 b = IERC20(wUST).balanceOf(address(this));
          console.log("Mock MockRouter IMockOperation.Type.DEPOSIT balanceOf MockRouter", b);
          console.log("Mock MockRouter IMockOperation.Type.DEPOSIT adress ", address(this));

          operation.initDepositStable(
              _operator,
              _amount,
              _swapper,
              _swapDest,
              _autoFinish
          );
          return address(operation);
      }

      if (_typ == IMockOperation.Type.REDEEM) {
          IERC20(aUST).safeTransferFrom(_msgSender(), address(this), _amount);
          operation.initRedeemStable(
              _operator,
              _amount,
              _swapper,
              _swapDest,
              _autoFinish
          );
          return address(operation);
      }

      revert("MockRouter: invalid operation type");
  }

  function depositStable(address _operator, uint256 _amount)
      public
      override
      returns (address)
  {
      return
          _init(
              IMockOperation.Type.DEPOSIT,
              _operator,
              _amount,
              address(0x0),
              address(0x0),
              true
          );
  }

  function redeemStable(address _operator, uint256 _amount)
      public
      override
      returns (address)
  {
      return
          _init(
              IMockOperation.Type.REDEEM,
              _operator,
              _amount,
              address(0x0),
              address(0x0),
              true
          );
  }

  function redeemStable(
      address _operator,
      uint256 _amount,
      address _swapper,
      address _swapDest
  ) public override returns (address) {
      return
          _init(
              IMockOperation.Type.REDEEM,
              _operator,
              _amount,
              _swapper,
              _swapDest,
              true
          );
  }

}
