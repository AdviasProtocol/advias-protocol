// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {IPriceConsumerV3} from './IPriceConsumerV3.sol';
import {IExchangeRateData} from '../interfaces/IExchangeRateData.sol';
import "hardhat/console.sol";

contract MockPriceConsumerV3 is IPriceConsumerV3, Ownable {
    using SafeMath for uint256;
    struct AssetPriceFeed {
        address asset;
        address priceFeed;
        address exchangeRateData;
        address exchangeRateUnderlyingAsset; // asset used to price
        uint8 exchangeRateDecimals;
        bool isYield;
    }

    mapping(address => AssetPriceFeed) internal _assetPriceFeeds;

    constructor() {}

    // !carefule!
    // will overlap previous set
    // function initAssetPriceFeed(address asset, address priceFeed) external onlyOwner {
    //     _assetPriceFeeds[asset] = priceFeed;
    // }

    function setAssetPriceFeed(address asset, address priceFeed, address exchangeRateData, address exchangeRateUnderlyingAsset, uint8 exchangeRateDecimals, bool isYield) external onlyOwner {
        require(asset != address(0), "Error: Asset cannot be 0x000");
        AssetPriceFeed storage assetPriceFeed = _assetPriceFeeds[asset];
        assetPriceFeed.asset = asset;
        assetPriceFeed.exchangeRateData = exchangeRateData;
        assetPriceFeed.exchangeRateUnderlyingAsset = exchangeRateUnderlyingAsset;
        assetPriceFeed.exchangeRateDecimals = 18;
        assetPriceFeed.isYield = isYield;
    }


    /**
     * Returns the latest price
     */
    function getLatestPrice(address asset) public view override returns (int) {
        AssetPriceFeed storage assetPriceFeed = _assetPriceFeeds[asset];
        // address priceFeedAddress = _assetPriceFeeds[asset];
        require(assetPriceFeed.asset != address(0), "Error: Price feed address is 0x000");
        int price;
        if (!assetPriceFeed.isYield) {
            price = int(1 * (10 ** 8));
        } else {
            // mimics price of a yield asset like aUST by taking the exchange rate mutliplied by underlying asset price
            ( , uint256 exchangeRate) = IExchangeRateData(assetPriceFeed.exchangeRateData).getInterestData();
            AssetPriceFeed storage exchangeAssetPriceFeed = _assetPriceFeeds[assetPriceFeed.exchangeRateUnderlyingAsset];
            uint256 _price = uint256(IPriceConsumerV3(address(this)).getLatestPrice(exchangeAssetPriceFeed.asset));
            uint8 priceDecimals = IPriceConsumerV3(address(this)).decimals(exchangeAssetPriceFeed.asset);
            price = int(exchangeRate.mul(_price).div(10**uint256(priceDecimals)));
        }
        return price;
    }

    function decimals(address asset) external view override returns (uint8) {
        AssetPriceFeed storage assetPriceFeed = _assetPriceFeeds[asset];
        if (!assetPriceFeed.isYield) {
            return uint8(8);
        } else {
            return assetPriceFeed.exchangeRateDecimals;
        }
    }

    // function getLatestPrice(address asset) public view override returns (int) {
    //     return int(1 * (10 ** 8));
    // }

    // function decimals(address asset) external view override returns (uint8) {
    //     return uint8(8);
    // }
}
