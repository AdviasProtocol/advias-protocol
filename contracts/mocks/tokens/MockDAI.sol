// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockDAI is ERC20 {
    constructor() ERC20("DAI Coin", "DAI") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function burn(uint256 amount, address to) public {
        _burn(to, amount);
    }

    function decimals() public view override returns (uint8) {
    		return 6;
  	}

}
