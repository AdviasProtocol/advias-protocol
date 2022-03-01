//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IPoolAddressesProvider} from '../interfaces/IPoolAddressesProvider.sol';
import {IPool} from '../interfaces/IPool.sol';

import '../tokens/DebtToken.sol';
import {IDebtTokenFactory} from '../interfaces/IDebtTokenFactory.sol';
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// import "hardhat/console.sol";

/**
 * @title DebtTokenFactory
 * @author Advias
 * @title Initiates debt token caller
 */
contract DebtTokenFactory is Initializable, UUPSUpgradeable, OwnableUpgradeable, IDebtTokenFactory {
/* contract DebtTokenFactory is IDebtTokenFactory { */
  IPoolAddressesProvider _provider;
  IPool _pool;

  function initialize(IPoolAddressesProvider provider) public initializer {
      _provider = provider;
      _pool = IPool(_provider.getPool());
  }

  function _authorizeUpgrade(address) internal override onlyOwner {}

  modifier onlyPoolAdmin() {
      require(msg.sender == _provider.getPoolAdmin(), "Errors: Caller must be pool admin");
      _;
  }

  // called directly after SavingsTokenFactory init
  /**
   * @dev Initiates debt token
   * @param asset The underlying asset
   * @param debtInterestRateFactor Percent of outside integration appreciation to account for
   * @param ltv Loan to value ratio
   **/
  function initDebtToken(
      address asset,
      uint256 debtInterestRateFactor,
      uint256 ltv
  ) external onlyPoolAdmin override {
      uint8 decimals = IERC20Metadata(asset).decimals();
      DebtToken debtTokenInstance = new DebtToken(
          address(_provider),
          asset,
          decimals
      );

      address debtWrappedAsset = address(debtTokenInstance);

      _pool.initDebtToken(
          asset,
          debtWrappedAsset,
          debtInterestRateFactor,
          ltv
      );

      emit DebtTokenDeployed(
          asset,
          debtWrappedAsset
      );

  }


}
