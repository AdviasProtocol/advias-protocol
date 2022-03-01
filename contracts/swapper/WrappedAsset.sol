// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
/* import {IERC20} from "./open-zeppelin/contracts/token/ERC20/IERC20.sol"; */

interface WrappedAsset is IERC20 {

    function mint(address to, uint256 amount) external;

    function burn(uint256 amount, address to) external;

}
