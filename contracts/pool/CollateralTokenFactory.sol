//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {IPoolAddressesProvider} from '../interfaces/IPoolAddressesProvider.sol';
import {IPool} from '../interfaces/IPool.sol';
import {ICollateralTokenFactory} from '../interfaces/ICollateralTokenFactory.sol';
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import '../tokens/CollateralToken.sol';
import '../tokens/YCollateralToken.sol';
import {ICollateralToken} from '../interfaces/ICollateralToken.sol';

// import "hardhat/console.sol";

/* contract CollateralTokenFactory is Initializable, UUPSUpgradeable, OwnableUpgradeable, ICollateralTokenFactory { */

/**
 * @title CollateralTokenFactory
 * @author Advias
 * @title Initiates collateral token caller
 */
contract CollateralTokenFactory is ICollateralTokenFactory {

  IPoolAddressesProvider _provider;
  IPool _pool;

  constructor(IPoolAddressesProvider provider) {
      _provider = provider;
      _pool = IPool(_provider.getPool());
  }

  modifier onlyPoolAdmin() {
      require(msg.sender == _provider.getPoolAdmin(), "Errors: Caller must be pool admin");
      _;
  }

  /**
   * @dev Initiates collateral token
   * @param asset The underlying asset
   * @param router The protocol asset router
   * @param exchangeRateData The protocol outside intergration exchange rate data
   * @param routerMinSupplyRedeemAmount Min outside intergration deposit and redeem amount
   * @param routerMaxSupplyRedeemAmount Max outside intergration deposit and redeem amount
   * @param collateralInterestRateFactor Percent of outside integration appreciation to account for
   * @param ctd Collateral to debt ratio
   **/
  function initCollateralToken(
      address asset,
      address router,
      address exchangeRateData,
      uint256 routerMinSupplyRedeemAmount,
      uint256 routerMaxSupplyRedeemAmount,
      uint256 collateralInterestRateFactor,
      uint256 ctd,
      bool isRoutable,
      bool isYield
  ) public override onlyPoolAdmin {
      uint8 decimals = IERC20Metadata(asset).decimals();
      address wrapped;
      if (isYield) {
        YCollateralToken collateralTokenInstance = new YCollateralToken(address(_provider), asset, decimals);
        wrapped = address(collateralTokenInstance);
      } else {
        CollateralToken collateralTokenInstance = new CollateralToken(address(_provider), asset, decimals);
        wrapped = address(collateralTokenInstance);
      }
      // address wrapped = address(collateralTokenInstance);
      _pool.initCollateralToken(
          asset,
          wrapped,
          router,
          exchangeRateData,
          routerMinSupplyRedeemAmount,
          routerMaxSupplyRedeemAmount,
          collateralInterestRateFactor,
          ctd,
          isRoutable
      );

      if (!isYield) {
        ICollateralToken(wrapped).initRouter();
      }
      
      emit CollateralTokenDeployed(
          asset,
          wrapped
      );

  }
}
