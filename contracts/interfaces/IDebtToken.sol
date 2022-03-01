//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {IRewardsBase} from '../tokens/IRewardsBase.sol';

interface IDebtToken {

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

  function mint(address account, uint256 amount, uint256 exchangeRate) external;

  /* function balanceOfPrincipal(address account) external view returns (uint256); */

  function burn(address account, uint256 amount, uint256 exchangeRate) external;

  function balanceOfScaled(address account) external view returns (uint256);

  function totalScaledSupply() external view returns (uint256);

  function getRewardsInstance() external view returns (IRewardsBase);

}
