// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {WadRayMath} from '../libraries/WadRayMath.sol';

import "@openzeppelin/contracts/access/Ownable.sol";
import {TokenBase} from './TokenBase.sol';

/**
 * @title Advias
 * @author Advias
 * @title Protocols token that extends dividend rewards
 */
contract Advias is TokenBase, Ownable {
    using SafeMath for uint256;
    using WadRayMath for uint256;

    constructor() TokenBase("Advias", "AVA") {
        _mint(msg.sender, 100000000 * (10 ** 18));
        _addDividendsBlacklist(msg.sender);
    }

    function _addDividendAsset(address asset) external onlyOwner {
        addDividendAsset(asset);
    }

    /**
     * @dev Adds an address to the dividend blacklist
     * @param user Address to blacklist
     **/
    function _addDividendsBlacklist(address user) public onlyOwner {
        addDividendsBlacklist(user);
    }

    /**
     * @dev Removes an address to the dividend blacklist
     * @param user Address to blacklist
     **/
    function _removeDividendsBlacklist(address user) public onlyOwner {
        removeDividendsBlacklist(user);
    }

}
