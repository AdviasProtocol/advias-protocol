//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IPool} from '../interfaces/IPool.sol';

import {WadRayMath} from '../libraries/WadRayMath.sol';
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPoolAddressesProvider} from '../interfaces/IPoolAddressesProvider.sol';
import {IDebtToken} from '../interfaces/IDebtToken.sol';
import {IPoolAssetData} from '../interfaces/IPoolAssetData.sol';
import {RewardsTokenBase} from './RewardsTokenBase.sol';
import {IRewardsBase} from './IRewardsBase.sol';

import "hardhat/console.sol";


// represents wUST deposited
contract DebtToken is RewardsTokenBase, IDebtToken {
  using SafeMath for uint256;
  using WadRayMath for uint256;
  using SafeERC20 for IERC20;

  uint8 immutable private _decimals;

  IPoolAddressesProvider public ADDRESSES_PROVIDER;
  IPoolAssetData private _poolAssetData;

  IPool private _pool;

  address internal _treasury; // where reserve factor goes as wrapped token
  address internal _vault; // where fees go as wrapped token

  address internal _underlyingAsset;

  mapping(address => uint256) private _initialExchangeRates;

  mapping(address => uint256) private _principalExchangeRates;
  mapping(address => uint256) private _principalBalanceScaled;

  mapping(address => uint256) private _principalBalance;

  mapping(address => mapping(address => uint256)) private _principalAssetBalance;

  IRewardsBase internal _rewardsBase;

  constructor(
      address provider,
      address underlyingAsset,
      uint8 decimals
  ) RewardsTokenBase("", "") {
      string memory underlyingAssetName = RewardsTokenBase(underlyingAsset).name();
      string memory underlyingAssetSymbol = RewardsTokenBase(underlyingAsset).symbol();

      string memory name = string(abi.encodePacked("Advia Debt Token ", underlyingAssetName));
      string memory symbol = string(abi.encodePacked("avaDebt", underlyingAssetSymbol));

      _decimals = decimals;
      _setDecimals(decimals);
      _setName(name);
      _setSymbol(symbol);

      ADDRESSES_PROVIDER = IPoolAddressesProvider(provider);
      _pool = IPool(ADDRESSES_PROVIDER.getPool());
      _poolAssetData = IPoolAssetData(ADDRESSES_PROVIDER.getPoolAssetData());
      _underlyingAsset = underlyingAsset;
  }

  function decimals() public view virtual override returns (uint8) {
      return _decimals;
  }

  modifier onlyRewardsTokenFactory() {
    require(msg.sender == address(ADDRESSES_PROVIDER.getRewardsTokenFactory()), "Error: Only rewards factory can be sender.");
    _;
  }

  /* function setRewards(address _rewards) external override onlyPool { */
  function setRewards(address _rewards) external override onlyRewardsTokenFactory {
      _rewardsBase = IRewardsBase(_rewards);
  }

  /* function initialize(
      IPoolAddressesProvider provider,
      address underlyingAsset
  ) public initializer {
      string memory underlyingAssetName = ERC20(underlyingAsset).name();
      string memory underlyingAssetSymbol = ERC20(underlyingAsset).symbol();

      string memory name = string(abi.encodePacked("Debt ", underlyingAssetName));
      string memory symbol = string(abi.encodePacked("C", underlyingAssetSymbol));

      __ERC20_init(name, symbol);

      ADDRESSES_PROVIDER = provider;

      _pool = IPool(ADDRESSES_PROVIDER.getPool());
      _underlyingAsset = underlyingAsset;
  }

  function _authorizeUpgrade(address) internal override onlyOwner {} */

  modifier onlyPool() {
    require(msg.sender == address(_pool), "Error: Only pool can be sender.");
    _;
  }

  modifier onlyPoolOrLiquidationCaller() {
    require(msg.sender == address(_pool) || msg.sender == ADDRESSES_PROVIDER.getLiquidationCaller(), "Error: Only pool can be sender.");
    _;
  }

  /**
   * @dev Mints avasTokenD to borrower that keeps track of debt balance
   **/
  function mint(address account, uint256 amount, uint256 exchangeRate) external override onlyPool {
      uint256 scaledAmount = amount.wadDiv(exchangeRate);
      uint256 currentTimestamp = block.timestamp;

      _principalBalance[account] = _principalBalance[account].add(amount);
      _initialExchangeRates[account] = exchangeRate;

      _mint(account, scaledAmount);
      emit Mint(account, amount, exchangeRate);
  }

  /**
   * @dev Balance of user avaToken as scaled
   * @param account Address of user
   **/
  function balanceOfScaled(address account) public view override returns (uint256) {
      return super.balanceOf(account);
  }

  /* function balanceOfPrincipal(address account) external view override returns (uint256) {
      return _principalBalance[account];
  } */

  /**
   * @dev Balance of user avaToken as scaled*exchangeRate
   * @param account Address of user
   * exchangeRate is simulated by using latest interest rate and last updated timestamp to now delta
   **/
  function balanceOf(address account) public view virtual override returns (uint256) {
      uint256 exchangeRate = _poolAssetData.simulateBorrowExchangeRate(_underlyingAsset);
      return super.balanceOf(account).wadMul(exchangeRate);
  }

  /**
   * @dev Burns avaToken and redeems AUST to UST
   * @param account Address to burn from
   * @param amount Amount to burn
   * @param exchangeRate AvasTokenD exchange rate
   **/
  function burn(address account, uint256 amount, uint256 exchangeRate) external override onlyPoolOrLiquidationCaller {

      uint256 scaledAmount = amount.wadDiv(exchangeRate);
      uint256 totalDebt = balanceOfScaled(account).wadMul(exchangeRate);
      uint256 debtInterest = totalDebt.sub(_principalBalance[account]);
      if (amount > debtInterest) {
          _principalBalance[account] =_principalBalance[account].sub(amount.sub(debtInterest));
      }
      _burn(account, scaledAmount);
      emit Burn(account, amount, exchangeRate);
  }

  /**
   * @dev total supply of avasTokenD as scaled
   **/
  function totalScaledSupply() external view override returns (uint256) {
      return super.totalSupply();
  }

  /**
   * @dev total supply of avasTokenD as scaled*exchangeRate
   * exchangeRate is simulated by using latest interest rate and last updated timestamp to now delta
   **/
  function totalSupply() public view virtual override returns (uint256) {
      uint256 exchangeRate = _poolAssetData.simulateBorrowExchangeRate(_underlyingAsset);
      return super.totalSupply().wadMul(exchangeRate);
  }


  /**
   * @dev For internal usage in the logic of the parent contract IncentivizedERC20
   **/
  function _getRewardsInstance() internal view override returns (IRewardsBase) {
      return _rewardsBase;
  }

  /**
   * @dev Returns the address of the incentives controller contract
   **/
  function getRewardsInstance() external view override returns (IRewardsBase) {
      return _getRewardsInstance();
  }


}
