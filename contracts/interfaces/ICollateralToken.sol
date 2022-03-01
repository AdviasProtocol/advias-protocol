//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface ICollateralToken {

  event RouterDeposit(
      address account,
      uint256 amount
  );

  event RouterRedeem(
      address account,
      uint256 amount
  );


  event Mint(
      address account,
      uint256 amount,
      uint256 exchangeRate
  );

  event Burn(
      address account,
      address recieverOfUnderlying,
      uint256 amount,
      uint256 exchangeRate
  );

  function initRouter() external;

  /* function deposit(address account, uint256 amount) external returns (bool); */

  /* function mintOnBorrow(address account, uint256 amount, uint256 exchangeRate) external; */

  function supplyLiquidityVault(address asset, address vault, uint256 bufferFactor) external;

  /* function balanceOfAndPrincipal(address account) external view returns (uint256); */

  function mint(address account, uint256 amount, uint256 exchangeRate, bool supply_) external returns (uint256, uint256);

  function mintToReserve(uint256 amount, uint256 exchangeRate) external;

  function burnToSavings(address account, uint256 amount, address _to, uint256 exchangeRate) external;

  function burnAndRedeem(address account, address receiver, address _toAsset, uint256 amount, uint256 exchangeRate) external returns (uint256);

  /* function burn(address account, address reciever, uint256 amount, uint256 exchangeRate) external; */

  /* function balanceOfAvailablePrincipal(address account) external view returns (uint256); */

  /* function balanceOfPrincipal(address account) external view returns (uint256); */

  function balanceOfScaled(address account) external view returns (uint256);

  function totalScaledSupply() external view returns (uint256);

  /* function effectivePrincipal(address user) external view returns (uint256); */

  /* function effectivePrincipalScaled(address user) external view returns (uint256); */

  /* function collateralAddress(address account) external view returns (address); */
}
