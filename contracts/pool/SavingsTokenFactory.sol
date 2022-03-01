//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

/* import "@openzeppelin/contracts/access/Ownable.sol"; */

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IPoolAddressesProvider} from '../interfaces/IPoolAddressesProvider.sol';
import {IPool} from '../interfaces/IPool.sol';
import {ISavingsTokenFactory} from '../interfaces/ISavingsTokenFactory.sol';
import {IAvaToken} from '../interfaces/IAvaToken.sol';

import '../tokens/YAvaToken.sol';
import '../tokens/AvaToken.sol';

import "hardhat/console.sol";

// handles creating savings and debt assets
/* contract SavingsTokenFactory is Initializable, UUPSUpgradeable, OwnableUpgradeable { */

/**
 * @title SavingsTokenFactory
 * @author Advias
 * @title Initiates an avaToken
 */
contract SavingsTokenFactory {
  IPoolAddressesProvider public _provider;
  IPool public _pool;

  constructor(IPoolAddressesProvider provider) {
      _provider = provider;
      _pool = IPool(_provider.getPool());
  }

  function initSavingsTokenFactory(IPoolAddressesProvider provider) external onlyPoolAdmin {
      _provider = provider;
      _pool = IPool(_provider.getPool());
  }

  struct InitSavingsParams {
      address asset;
      uint256 depositsSuppliedInterestRateFactor;
      uint256 routerMinSupplyRedeemAmount;
      address provider;
      bool isRoutable; // if local blockchain asset
  }

  modifier onlyPoolAdmin() {
      require(msg.sender == _provider.getPoolAdmin(), "Errors: Caller must be pool admin");
      _;
  }

  /**
   * @dev Initiates avasToken savings
   * @param asset Underlying asset of avasToken
   * @param router Address for router for avasToken for outside integration for asset appreciation
   * @param exchangeRateData Address for exchange and interest rate data for the Router underlying asset
   * @param depositsSuppliedInterestRateFactor Percent of outside integration appreciation to account
   * @param routerMinSupplyRedeemAmount Min amount to transfer to and from outside integration
   **/
  function initSavings(
      address asset,
      address router,
      address exchangeRateData,
      uint256 depositsSuppliedInterestRateFactor,
      uint256 routerMinSupplyRedeemAmount, // min amount Router allows
      bool isRoutable
  ) external onlyPoolAdmin {
      InitSavingsParams memory params;
      params.asset = asset;
      params.depositsSuppliedInterestRateFactor = depositsSuppliedInterestRateFactor;
      params.routerMinSupplyRedeemAmount = routerMinSupplyRedeemAmount;
      params.provider = address(_provider);
      params.isRoutable = isRoutable;
      address wrapped;
      uint8 decimals = IERC20Metadata(asset).decimals();
      if (params.isRoutable) {
          AvaToken avaTokenInstance = new AvaToken(params.provider, params.asset, decimals);
          wrapped = address(avaTokenInstance);
      } else {
          YAvaToken avaTokenInstance = new YAvaToken(params.provider, params.asset, decimals);
          wrapped = address(avaTokenInstance);
      }
      // init struct
      IPool(address(_pool)).initSavingsToken(
          params.asset,
          wrapped,
          router,
          exchangeRateData,
          params.routerMinSupplyRedeemAmount,
          params.depositsSuppliedInterestRateFactor,
          params.isRoutable
      );
      if (params.isRoutable) {
          IAvaToken(wrapped).initRouter();
      }
  }
}
