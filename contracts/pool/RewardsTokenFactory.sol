//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IRewardsTokenBase} from '../tokens//IRewardsTokenBase.sol';

import {IPool} from '../interfaces/IPool.sol';
import {IPoolAddressesProvider} from '../interfaces/IPoolAddressesProvider.sol';
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";

/* import "@openzeppelin/contracts/access/Ownable.sol"; */


/**
 * @title RewardsTokenFactory
 * @author Advias
 * @title Sets the rewards base contract address in the avaToken
 */
contract RewardsTokenFactory is Initializable, UUPSUpgradeable, OwnableUpgradeable {
/* contract RewardsTokenFactory is Ownable { */
  IPoolAddressesProvider _provider;
  IPool public _pool;

  event RewardsDeployed(
      address _rewardsBase,
      address wrappedAsset
  );

  function initialize(IPoolAddressesProvider provider) public initializer {
      _provider = provider;
      _pool = IPool(_provider.getPool());
      __Ownable_init();
  }

  function _authorizeUpgrade(address) internal override onlyOwner {}

  modifier onlyPoolAdmin() {
      require(msg.sender == _provider.getPoolAdmin(), "Errors: Caller must be pool admin");
      _;
  }

  /**
   * @dev Initiates avasToken savings to generate awards as the first step
   * @param rewardsBase Address of the rewards base
   * @param wrapped AvasToken
   **/
  function initRewards(
      address rewardsBase,
      address wrapped
  ) external onlyPoolAdmin {
      IRewardsTokenBase(wrapped).setRewards(
          rewardsBase
      );
  }


}
