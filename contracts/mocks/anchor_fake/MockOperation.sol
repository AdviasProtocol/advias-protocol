// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;

import {SafeMath} from "./open-zeppelin/contracts/math/SafeMath.sol";
import {IERC20} from "./open-zeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "./open-zeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Context} from "./open-zeppelin/contracts/utils/Context.sol";

import {WrappedAssetV1} from "./WrappedAssetV1.sol";
import {ISwapperV1} from "../../interfaces/ISwapperV1.sol";

import {IMockExchangeRateFeeder} from "./MockExchangeRateFeeder.sol";
import "hardhat/console.sol";

library WadRayMath1 {
  uint256 internal constant WAD = 1e18;
  uint256 internal constant halfWAD = WAD / 2;

  uint256 internal constant RAY = 1e27;
  uint256 internal constant halfRAY = RAY / 2;

  uint256 internal constant WAD_RAY_RATIO = 1e9;

  /**
   * @return One ray, 1e27
   **/
  function ray() internal pure returns (uint256) {
    return RAY;
  }

  /**
   * @return One wad, 1e18
   **/

  function wad() internal pure returns (uint256) {
    return WAD;
  }

  /**
   * @return Half ray, 1e27/2
   **/
  function halfRay() internal pure returns (uint256) {
    return halfRAY;
  }

  /**
   * @return Half ray, 1e18/2
   **/
  function halfWad() internal pure returns (uint256) {
    return halfWAD;
  }

  /**
   * @dev Multiplies two wad, rounding half up to the nearest wad
   * @param a Wad
   * @param b Wad
   * @return The result of a*b, in wad
   **/
  function wadMul(uint256 a, uint256 b) internal pure returns (uint256) {
    if (a == 0 || b == 0) {
      return 0;
    }

    require(a <= (type(uint256).max - halfWAD) / b, "Errors.MATH_MULTIPLICATION_OVERFLOW");

    return (a * b + halfWAD) / WAD;
  }

  /**
   * @dev Divides two wad, rounding half up to the nearest wad
   * @param a Wad
   * @param b Wad
   * @return The result of a/b, in wad
   **/
  function wadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b != 0, "Errors.MATH_DIVISION_BY_ZERO");
    uint256 halfB = b / 2;

    require(a <= (type(uint256).max - halfB) / WAD, "Errors.MATH_MULTIPLICATION_OVERFLOW");

    return (a * WAD + halfB) / b;
  }

  /**
   * @dev Multiplies two ray, rounding half up to the nearest ray
   * @param a Ray
   * @param b Ray
   * @return The result of a*b, in ray
   **/
  function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
    if (a == 0 || b == 0) {
      return 0;
    }

    require(a <= (type(uint256).max - halfRAY) / b, "Errors.MATH_MULTIPLICATION_OVERFLOW");

    return (a * b + halfRAY) / RAY;
  }

  /**
   * @dev Divides two ray, rounding half up to the nearest ray
   * @param a Ray
   * @param b Ray
   * @return The result of a/b, in ray
   **/
  function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b != 0, "Errors.MATH_DIVISION_BY_ZERO");
    uint256 halfB = b / 2;

    require(a <= (type(uint256).max - halfB) / RAY, "Errors.MATH_MULTIPLICATION_OVERFLOW");

    return (a * RAY + halfB) / b;
  }

  /**
   * @dev Casts ray down to wad
   * @param a Ray
   * @return a casted to wad, rounded half up to the nearest wad
   **/
  function rayToWad(uint256 a) internal pure returns (uint256) {
    uint256 halfRatio = WAD_RAY_RATIO / 2;
    uint256 result = halfRatio + a;
    require(result >= halfRatio, "Errors.MATH_ADDITION_OVERFLOW");

    return result / WAD_RAY_RATIO;
  }

  /**
   * @dev Converts wad up to ray
   * @param a Wad
   * @return a converted in ray
   **/
  function wadToRay(uint256 a) internal pure returns (uint256) {
    uint256 result = a * WAD_RAY_RATIO;
    require(result / WAD_RAY_RATIO == a, "Errors.MATH_MULTIPLICATION_OVERFLOW");
    return result;
  }
}

interface IMockOperation {
    // Events
    event AutoFinishEnabled(address indexed operation);
    event InitDeposit(address indexed operator, uint256 amount, address to);
    event FinishDeposit(address indexed operator, uint256 amount);
    event InitRedemption(address indexed operator, uint256 amount, address to);
    event FinishRedemption(address indexed operator, uint256 amount);
    event EmergencyWithdrawActivated(address token, uint256 amount);

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

    function terraAddress() external view returns (address);

    /* function getCurrentStatus() external view returns (Info memory); */

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

    /* function halt() external; */

    /* function recover() external; */

    /* function emergencyWithdraw(address _token, address _to) external; */

    /* function emergencyWithdraw(address payable _to) external; */
}

contract MockOperation is Context, IMockOperation {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;
  using SafeERC20 for WrappedAssetV1;
  using WadRayMath1 for uint256;

  address public owner;
  address public operator;

  address public router;
  address public controller;
  address public exchangeRateFeeder;

  Info public DEFAULT_STATUS =
      Info({
          status: Status.IDLE,
          typ: Type.NEUTRAL,
          operator: address(0x0),
          amount: 0,
          input: address(0x0),
          output: address(0x0),
          swapper: address(0x0),
          swapDest: address(0x0)
      });

  /* bytes32 public override terraAddress; */

  address public override terraAddress;


  Info public currentStatus;

  WrappedAssetV1 public wUST;
  WrappedAssetV1 public aUST;

  modifier checkStopped {
      require(currentStatus.status != Status.STOPPED, "Operation: stopped");

      _;
  }

  modifier onlyGranted {
      address sender = _msgSender();
      require(
          sender == owner || sender == router || sender == controller,
          "OperationACL: denied"
      );

      _;
  }

  /* function initialize(
      address _router,
      //address _controller,
      bytes32 _terraAddress,
      address _wUST,
      address _aUST
  ) public initializer {
      //(
      //    address _router,
      //    address _controller,
      //    bytes32 _terraAddress,
      //    address _wUST,
      //    address _aUST
      //) = abi.decode(args, (address, address, bytes32, address, address));

      currentStatus = DEFAULT_STATUS;
      terraAddress = address(0);
      wUST = WrappedAssetV1(_wUST);
      aUST = WrappedAssetV1(_aUST);

      router = _router;
      //controller = _controller;
  } */

  constructor(
      /* address _router, */
      address _terraAddress,
      address _wUST,
      address _aUST,
      address _exchangeRateFeeder
  ) {
      currentStatus = DEFAULT_STATUS;
      terraAddress = address(this);
      wUST = WrappedAssetV1(_wUST);
      aUST = WrappedAssetV1(_aUST);

      /* router = _router; */
      exchangeRateFeeder = _exchangeRateFeeder;
  }


  function _init(
      Type _typ,
      address _operator,
      uint256 _amount,
      address _swapper,
      address _swapDest,
      bool _autoFinish
  ) private checkStopped {
      require(currentStatus.status == Status.IDLE, "Operation: running");
      require(_amount >= 10 ether, "Operation: amount must be more than 10");
      console.log("Mock Operation after requires");

      currentStatus = Info({
          status: Status.RUNNING,
          typ: _typ,
          operator: _operator,
          amount: _amount,
          input: address(0x0),
          output: address(0x0),
          swapper: _swapper,
          swapDest: _swapDest
      });

      if (_typ == Type.DEPOSIT) {
          console.log("Mock Operation start Type.DEPOSIT");

          currentStatus.input = address(wUST);
          currentStatus.output = address(aUST);

          console.log("Mock Operation start Type.DEPOSIT wUST", address(wUST));
          console.log("Mock Operation start Type.DEPOSIT _msgSender()", _msgSender());
          console.log("Mock Operation start Type.DEPOSIT _amount", _amount);

          wUST.safeTransferFrom(_msgSender(), address(this), _amount);
          console.log("Mock Operation start Type.DEPOSIT after safeTransferFrom");

          wUST.burn(_amount, terraAddress);
          console.log("Mock Operation start Type.DEPOSIT after burn");

          /* IMockExchangeRateFeeder(exchangeRateFeeder).update(address(wUST)); */
          uint256 exchangeRate = IMockExchangeRateFeeder(exchangeRateFeeder).exchangeRateOf(address(wUST), true);

          uint256 _mint = _amount.wadDiv(exchangeRate);
          aUST.mint(address(this), _mint);

          emit InitDeposit(_operator, _amount, terraAddress);

          finish();
      } else if (_typ == Type.REDEEM) {
          console.log("we are redeeeeeeeeming");
          currentStatus.input = address(aUST);
          currentStatus.output = address(wUST);

          aUST.safeTransferFrom(_msgSender(), address(this), _amount);
          aUST.burn(_amount, terraAddress);

          /* IMockExchangeRateFeeder(exchangeRateFeeder).update(address(wUST)); */
          uint256 exchangeRate = IMockExchangeRateFeeder(exchangeRateFeeder).exchangeRateOf(address(wUST), true);

          uint256 _mint = _amount.wadMul(exchangeRate);
          wUST.mint(address(this), _mint);


          emit InitRedemption(_operator, _amount, terraAddress);

          finish();
      } else {
          revert("Operation: invalid operation type");
      }

      if (_autoFinish) {
          emit AutoFinishEnabled(address(this));
      }
  }

  function initDepositStable(
      address _operator,
      uint256 _amount,
      address _swapper,
      address _swapDest,
      bool _autoFinish
  ) public override {
      _init(
          Type.DEPOSIT,
          _operator,
          _amount,
          _swapper,
          _swapDest,
          _autoFinish
      );
  }

  function initRedeemStable(
      address _operator,
      uint256 _amount,
      address _swapper,
      address _swapDest,
      bool _autoFinish
  ) public override {
      _init(
          Type.REDEEM,
          _operator,
          _amount,
          _swapper,
          _swapDest,
          _autoFinish
      );
  }

  function _finish(uint256 _minAmountOut)
      private
      checkStopped
      returns (address, uint256)
  {
      // check status
      require(currentStatus.status == Status.RUNNING, "Operation: idle");

      WrappedAssetV1 output = WrappedAssetV1(currentStatus.output);
      uint256 amount = output.balanceOf(address(this));

      address operator = currentStatus.operator;
      address swapper = currentStatus.swapper;

      require(amount > 0, "Operation: not enough token");

      if (swapper != address(0x0)) {
          console.log("Mock Operation swapper != address", swapper);

          output.safeIncreaseAllowance(swapper, amount);

          try
              ISwapperV1(swapper).swapToken(
                  address(output),
                  currentStatus.swapDest,
                  amount,
                  _minAmountOut,
                  operator
              )
          {} catch {
              console.log("Mock Operation _finish catch operator", operator);
              console.log("Mock Operation _finish catch amount", amount);

              uint256 amount_ = amount.wadMul(uint256(1e18).sub(uint256(1000000000000000)));
              console.log("Mock Operation _finish else amount_", amount_);

              output.safeDecreaseAllowance(swapper, amount_);
              output.safeTransfer(operator, amount_);


              /* output.safeDecreaseAllowance(swapper, amount);
              output.safeTransfer(operator, amount); */
          }
      } else {
          console.log("Mock Operation _finish else operator", operator);
          console.log("Mock Operation _finish else amount", amount);
          uint256 amount_ = amount.wadMul(uint256(1e18).sub(uint256(1000000000000000)));
          console.log("Mock Operation _finish else amount_", amount_);

          /* output.safeTransfer(operator, amount); */
          output.safeTransfer(operator, amount_);

      }


      /* output.safeTransfer(operator, amount); // edit */

      // state reference gas optimization
      Type typ = currentStatus.typ;

      if (typ == Type.DEPOSIT) {
          emit FinishDeposit(operator, amount);
      } else if (typ == Type.REDEEM) {
          emit FinishRedemption(operator, amount);
      }

      // reset
      currentStatus = DEFAULT_STATUS;
      console.log("_finish eend");

      return (address(output), amount);
  }

  function finish() public override {
      _finish(0);
  }

  function finish(uint256 _minAmountOut) public override {
      _finish(_minAmountOut);
  }

  function finishDepositStable() public override {
      _finish(0);
  }

  function finishRedeemStable() public override {
      _finish(0);
  }


}
