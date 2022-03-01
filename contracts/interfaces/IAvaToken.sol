//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {IRewardsBase} from '../tokens/IRewardsBase.sol';

// all underlying gets sent to anchor
interface IAvaToken  {

  event Mint(
      address account,
      uint256 amount,
      uint256 exchangeRate
  );

  event Burn(
      address account,
      uint256 amount,
      uint256 exchangeRate
  );

  event RouterDeposit(
      uint256 amount
  );

  event RouterRedeem(
      address account,
      uint256 amount
  );

  function mint_(address account, uint256 amount, uint256 supplyAmount, uint256 exchangeRate) external;

  function setDividends(address to, uint256 factor) external;

  function mintToSharedTreasury(uint256 amount, uint256 exchangeRate) external;

  function burn(address account, uint256 amount, uint256 redeemedAmount, uint256 exchangeRate) external;

  function initRouter() external;

  function balanceOfScaled(address account) external view returns (uint256);

  function totalScaledSupply() external view returns (uint256);

  function dividendSupply() external view returns (uint256);

  function supplyLiquidityVault(address asset, address vault, uint256 bufferFactor) external;

  function supply(
      uint256 amount
  ) external returns (uint256);

  function burnTo(address account, uint256 amount, address _to, uint256 exchangeRate) external;

  function redeem(uint256 amount, address to, bool emergency) external returns (bool);

  function lendableTotalSupply() external view returns (uint256);

  function lendableTotalSupplyPrincipal() external view returns (uint256);

  function routerSuppliedTotalScaledSupply() external view returns (uint256);

  function routerSuppliedTotalSupply() external view returns (uint256);

  function routerSuppliedScaledBalance() external view returns (uint256);
  
  function transferUnderlyingTo(address account, uint256 amount) external returns (uint256);

  function getRewardsInstance() external view returns (IRewardsBase);

  function getRouterUnderlying() external view returns (address);

}
