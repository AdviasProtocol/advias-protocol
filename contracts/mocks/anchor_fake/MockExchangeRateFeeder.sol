// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;

import {SafeMath} from "./open-zeppelin/contracts/math/SafeMath.sol";
import {Ownable} from "./open-zeppelin/contracts/access/Ownable.sol";

import "hardhat/console.sol";

interface IMockExchangeRateFeeder {
    event RateUpdated(
        address indexed _operator,
        address indexed _token,
        uint256 _before,
        uint256 _after,
        uint256 _updateCount
    );

    enum Status {NEUTRAL, RUNNING, STOPPED}

    struct Token {
        Status status;
        uint256 exchangeRate;
        uint256 period;
        uint256 weight;
        uint256 lastUpdatedAt;
    }

    function exchangeRateOf(address _token, bool _simulate)
        external
        view
        returns (uint256);

    function update(address _token) external;
}

interface IMockExchangeRateFeederGov {
    function addToken(
        address _token,
        uint256 _baseRate,
        uint256 _period,
        uint256 _weight
    ) external;

    function startUpdate(address[] memory _tokens) external;

    function stopUpdate(address[] memory _tokens) external;
}

contract MockExchangeRateFeeder is IMockExchangeRateFeeder, Ownable {
    using SafeMath for uint256;


    mapping(address => Token) public tokens;

    constructor() {}

    function addToken(
        address _token,
        uint256 _baseRate,
        uint256 _period,
        uint256 _weight
    ) public {
        tokens[_token] = Token({
            status: Status.NEUTRAL,
            exchangeRate: _baseRate,
            period: _period,
            weight: _weight,
            lastUpdatedAt: block.timestamp
        });
    }

    function startUpdate(address[] memory _tokens) public {
        for (uint256 i = 0; i < _tokens.length; i++) {
            tokens[_tokens[i]].status = Status.RUNNING;
            tokens[_tokens[i]].lastUpdatedAt = block.timestamp; // reset
        }
    }

    function stopUpdate(address[] memory _tokens) public {
        for (uint256 i = 0; i < _tokens.length; i++) {
            tokens[_tokens[i]].status = Status.STOPPED;
        }
    }

    function exchangeRateOf(address _token, bool _simulate)
        public
        view
        override
        returns (uint256)
    {
        uint256 exchangeRate = tokens[_token].exchangeRate;

        if (_simulate) {
            Token memory token = tokens[_token];

            uint256 elapsed = block.timestamp.sub(token.lastUpdatedAt);
            /* if (elapsed == 0) { return exchangeRate; } */
            /* console.log("exchangeRateOf elapsed", elapsed); */
            /* console.log("exchangeRateOf token.period", token.period); */

            uint256 updateCount = elapsed.div(token.period);
            for (uint256 i = 0; i < updateCount; i++) {
                exchangeRate = exchangeRate.mul(token.weight).div(1e18);
            }
        }
        /* console.log("exchangeRatOf exchangeRate", exchangeRate); */

        return exchangeRate;
    }

    function update(address _token) public override {
        Token memory token = tokens[_token];
        /* console.log("update _token", _token); */

        require(token.status == Status.RUNNING, "Feeder: invalid status");
        /* console.log("update Status.RUNNING"); */

        uint256 elapsed = block.timestamp.sub(token.lastUpdatedAt);
        if (elapsed < token.period) {
            return;
        }
        /* console.log("update elapsed", elapsed); */
        /* console.log("update token.period", token.period); */

        uint256 updateCount = elapsed.div(token.period);
        uint256 exchangeRateBefore = token.exchangeRate; // log
        for (uint256 i = 0; i < updateCount; i++) {
            token.exchangeRate = token.exchangeRate.mul(token.weight).div(1e18);
        }
        token.lastUpdatedAt = block.timestamp;
        /* console.log("update Statoken.lastUpdatedAtING", token.lastUpdatedAt); */

        tokens[_token] = token;

        emit RateUpdated(
            msg.sender,
            _token,
            exchangeRateBefore,
            token.exchangeRate,
            updateCount
        );
    }
}
