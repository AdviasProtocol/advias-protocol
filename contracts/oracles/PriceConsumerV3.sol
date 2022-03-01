// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {IPriceConsumerV3} from './IPriceConsumerV3.sol';
import {IExchangeRateData} from '../interfaces/IExchangeRateData.sol';

/**
 * @title PriceConsumerV3
 * @author Advias
 * @title Chainlink pricing oracles
 * updated to be used with exchange rates to simulate pricing of a yielding asset with indexing
 */
contract PriceConsumerV3 is IPriceConsumerV3, Ownable {

    // mapping(address => address) private _assetPriceFeeds;

    struct AssetPriceFeed {
        address asset;
        address priceFeed;
        address exchangeRateData;
        uint8 exchangeRateDecimals;
    }

    mapping(address => AssetPriceFeed) internal _assetPriceFeeds;


    /**
     * Network: Mainnet
     * Aggregator: UST/USD
     * Address: 0x8b6d9085f310396C6E4f0012783E9f850eaa8a82
     */
    constructor() {}

      // !carefule!
      // will overlap previous set
    // function initAssetPriceFeed(address asset, address priceFeed) external onlyOwner {
    //     _assetPriceFeeds[asset] = priceFeed;
    // }

    function setAssetPriceFeed(address asset, address priceFeed, address exchangeRateData, uint8 exchangeRateDecimals) external onlyOwner {
        require(asset != address(0), "Error: Asset cannot be 0x000");
        AssetPriceFeed storage assetPriceFeed = _assetPriceFeeds[asset];
        assetPriceFeed.asset = asset;
        assetPriceFeed.exchangeRateData = exchangeRateData;
        assetPriceFeed.exchangeRateDecimals = 18;
    }


    /**
     * Returns the latest price
     */
    function getLatestPrice(address asset) public view override returns (int) {
        AssetPriceFeed storage assetPriceFeed = _assetPriceFeeds[asset];
        // address priceFeedAddress = _assetPriceFeeds[asset];
        require(assetPriceFeed.asset != address(0), "Error: Price feed address is 0x000");
        int price;
        if (assetPriceFeed.exchangeRateData != address(0)) {
            require(assetPriceFeed.priceFeed != address(0), "Error: Price feed address is 0x000");
            AggregatorV3Interface priceFeed = AggregatorV3Interface(assetPriceFeed.priceFeed);
            ( , price, , , ) = priceFeed.latestRoundData();
        } else {
            ( , uint256 _price) = IExchangeRateData(assetPriceFeed.exchangeRateData).getInterestData();
            price = int(price);
        }
        return price;
    }

    function decimals(address asset) external view override returns (uint8) {
        AssetPriceFeed storage assetPriceFeed = _assetPriceFeeds[asset];
        if (assetPriceFeed.exchangeRateData != address(0)) {
            // address priceFeedAddress = _assetPriceFeeds[asset];
            require(assetPriceFeed.priceFeed != address(0), "Error: Price feed address is 0x000");
            AggregatorV3Interface priceFeed = AggregatorV3Interface(assetPriceFeed.priceFeed);
            return priceFeed.decimals();
        } else {
            return assetPriceFeed.exchangeRateDecimals;
        }
    }

}
