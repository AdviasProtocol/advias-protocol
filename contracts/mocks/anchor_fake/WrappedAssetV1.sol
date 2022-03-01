// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

import {IERC20} from "./open-zeppelin/contracts/token/ERC20/IERC20.sol";

interface WrappedAssetV1 is IERC20 {

    function mint(address to, uint256 amount) external;

    function burn(uint256 amount, address to) external;

}
