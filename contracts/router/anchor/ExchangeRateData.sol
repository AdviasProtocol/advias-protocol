// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IExchangeRateFeeder} from "./interfaces/IExchangeRateFeeder.sol";
import {ExchangeRateFeederData} from './interfaces/IExchangeRateFeeder.sol';
import {WadRayMath} from '../../libraries/WadRayMath.sol';
import {IExchangeRateData} from '../../interfaces/IExchangeRateData.sol';
import {IPoolAddressesProvider} from '../../interfaces/IPoolAddressesProvider.sol';

import "hardhat/console.sol";

// swaps assets to UST to send to routere for deposit or redeem

/**
 * @title ExchangeRateData
 * @author Advias
 * @title Responsible for retrieving interest and exchange rate information from outside protocols like Anchor' or aggregated together
 * Each contract should represent the ER of one asset or class asset
 * Currently, Advias uses Anchor as a sole yield provider and all stable assets are swapped to UST and deposited
 * Each stable asset uses this specific contract to get rates since ultimately, they are UST
 * 
 * Aggregation
 * This contract can be expanded to be used in aggregated assets through noded contracts
 * If we were to aggregate one depositable asset to an array multiple protocols, we would display the return value exchange rate as the aggregated
 * total balance of each vs rate accrued from previous total aggregrated balance
 * exchangeRate = previousExchangeRate*((currentBalance-previousBalance)/previousBalance)+previousExchangeRate
 */
contract ExchangeRateData is IExchangeRateData {
    using SafeMath for uint256;
    using WadRayMath for uint256;

    IERC20 private AUST;
    IERC20 private UST;

    IPoolAddressesProvider private addressesProvider;
    uint256 constant ONE  = 1e18;

    IExchangeRateFeeder public feeder;
    ExchangeRateFeederData public feederData;

    uint256 public ONE_YR;

    enum Status {NEUTRAL, RUNNING, STOPPED}

    struct TokenData {
        ExchangeRateFeederData.Status status;
        uint256 exchangeRate;
        uint256 period;
        uint256 weight;
        uint256 lastUpdatedAt;
        uint256 interestRate; //ray
    }

    TokenData public tokenData;

    function _tokenData() external view returns (TokenData memory) {
        return tokenData;
    }

    modifier onlyPoolAdmin() {
        require(msg.sender == addressesProvider.getPoolAdmin());
        _;
    }

    constructor(
        address _addressesProvider,
        address _feeder,
        address _AUST,
        address _UST
    ) {
        AUST = IERC20(_AUST);
        UST = IERC20(_UST);
        ONE_YR = 31536000;
        addressesProvider = IPoolAddressesProvider(_addressesProvider);
        feeder = IExchangeRateFeeder(_feeder);
        feederData = ExchangeRateFeederData(_feeder);
        initData();
    }

    function setAddressesProvider(address _addressesProvider) public onlyPoolAdmin {
        addressesProvider = IPoolAddressesProvider(_addressesProvider);
    }

    function updateOneYear(uint256 x) public onlyPoolAdmin {
        ONE_YR = x;
    }

    function setExchangeRateFeederData(address _feederData) public onlyPoolAdmin {
        feederData = ExchangeRateFeederData(_feederData);
    }

    function setExchangeRateFeeder(address _exchangeRateFeeder)
        public
        onlyPoolAdmin
    {
        feeder = IExchangeRateFeeder(_exchangeRateFeeder);
    }

    /**
     * @dev Initiates data and saves
     */
    function initData() internal {
        (   ExchangeRateFeederData.Status status,
            uint256 exchangeRate,
            uint256 period,
            uint256 weight,
            uint256 lastUpdatedAt
        ) = feederData.tokens(address(UST));

        // apr
        uint256 interestRate = weight.sub(1e18).mul(ONE_YR.div(period));
        tokenData = TokenData({
            status: status,
            exchangeRate: exchangeRate,
            period: period,
            weight: weight,
            lastUpdatedAt: lastUpdatedAt,
            interestRate: interestRate
        });
    }

    /**
     * @dev Updates data
     */
    function getInterestDataUpdated() public override onlyPoolAdmin returns (uint256, uint256) {
        (   ExchangeRateFeederData.Status status,
            uint256 exchangeRate,
            uint256 period,
            uint256 weight,
            uint256 lastUpdatedAt
        ) = feederData.tokens(address(UST));

        uint256 _weight = tokenData.weight;
        uint256 _period = tokenData.period;

        // apr
        uint256 interestRate = weight.sub(1e18).mul(ONE_YR.div(period));

        tokenData = TokenData({
            status: status,
            exchangeRate: exchangeRate,
            period: period,
            weight: weight,
            lastUpdatedAt: lastUpdatedAt,
            interestRate: interestRate
        });

        return (interestRate, exchangeRate);
    }

    function getInterestData(address asset) external view override returns (uint256, uint256) {
        return getInterestData();
    }

    /**
     * @dev Returns interest and exchange rate as wad
     */
    function getInterestData() public view override returns (uint256, uint256) {
        (   ExchangeRateFeederData.Status status,
            uint256 exchangeRate,
            uint256 period,
            uint256 weight,
            uint256 lastUpdatedAt
        ) = feederData.tokens(address(UST));
        // apr
        uint256 interestRate = weight.sub(1e18).mul(ONE_YR.div(period));
        uint256 currentTimestamp = block.timestamp;
        uint256 timeDelta = currentTimestamp.sub(lastUpdatedAt);
        uint256 _exchangeRate = calculateSimulatedExchangeRate(exchangeRate, timeDelta, interestRate);
        return (interestRate, _exchangeRate);

    }

    /**
     * @dev Simulates exchange rate if the protocol we are calling has large intermitents
     */
    function calculateSimulatedExchangeRate(uint256 previousIndex, uint256 timeDelta, uint256 rate) internal view returns (uint256) {
        if (timeDelta == 0) {
            return previousIndex;
        }
        // inspired by aave p
        return rate.div(ONE_YR).add(ONE).wadPow(timeDelta).wadMul(previousIndex);
    }

}
