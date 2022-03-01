// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "hardhat/console.sol";

contract aDAI is ERC20, Ownable {
    constructor() ERC20("Anchor DAI", "aDAI") {}

    function mint(address to, uint256 amount) public {
        console.log("Minting aDAI", to, amount);
        _mint(to, amount);
    }

    function burn(uint256 amount, address to) public {
        console.log("Burn aDAI", to, amount);
        _burn(msg.sender, amount);
    }

}
