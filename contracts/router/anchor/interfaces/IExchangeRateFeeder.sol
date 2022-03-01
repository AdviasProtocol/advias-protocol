// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IExchangeRateFeeder {
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

abstract contract ExchangeRateFeederData is IExchangeRateFeeder {
    mapping(address => Token) public tokens;

    function exchangeRateOf(address _token, bool _simulate)
        external
        view
        virtual
        override
        returns (uint256);

    function update(address _token) external virtual override;

}
