//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface ISavingsBase {
    function balanceOf(address account, uint256 id) external view returns (uint256);
}
