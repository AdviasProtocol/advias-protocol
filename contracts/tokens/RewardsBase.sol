//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {WadRayMath} from '../libraries/WadRayMath.sol';
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IRewardsBase} from './IRewardsBase.sol';
import {IAvaToken} from '../interfaces/IAvaToken.sol';

/*
inspired by aave incentives controller
*/

contract RewardsBase is IRewardsBase {
    using SafeMath for uint256;
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;

    mapping(address => uint256) internal _usersUnclaimedRewards; // all reward tokens not yet claimed for each asset
    uint256 public totalSupplyRewarded; // tracks overall rewarded includes unclaimed
    uint256 internal totalAllottedSupply; // total balance being allotted towards rewards + on configureRewardAsset, - on claims

    // each wrapped asset
    struct RewardAssetData {
        address rewardsToken; // protocol token - tradeable
        uint256 lastUpdateTimestamp;
        uint256 totalSupply;
    }

    RewardAssetData public rewardAsset;

    /**
     * @dev Each avasToken data
     **/
    struct AssetData {
        address asset;
        uint256 start;
        uint256 end; // not used
        uint256 exchangeRate;
        uint256 lastUpdateTimestamp;
        uint256 tokensPerSecond; // amount of Advias to reward per second
        uint256 totalTokenSupply; // current avaToken supply
        uint256 totalRewardSupply; // ttotal amount allotted for rewards
        uint256 totalSupplyRewarded; // totalRewardSupply rewarded
        uint256 unclaimedRewards;
        bool exists;
    }

    mapping(address => AssetData) public assetsData;

    uint8 public constant PRECISION = 18;

    /**
     * @dev Each users data who receives rewards as a mapping from AssetData
     **/
    struct UserData {
        uint256 exchangeRate;
        uint256 previousBalance;
        uint256 claimedRewards;
        uint256 unclaimedRewards;
    }

    mapping(address => mapping(address => UserData)) public usersData;

    mapping(uint256 => address) public assetsList;
    uint256 public assetsCount;

    uint256 private ONE_YR = 31536000;

    IERC20 public rewardsToken;

    mapping (address => uint256) public rewards; // amount rewarded

    constructor(
        IERC20 _rewardToken
    ) {
        rewardsToken = _rewardToken;
    }

    /**
     * @dev Each users data who receives rewards as a mapping from AssetData
     * @param asset AvasToken address
     * @param startNow If to start reward on this timestamp
     * @param start Timestamp to start accruing rewards
     * @param end End of rewards distribution timestamp
     * @param _totalRewardSupply How much AVA to allot to this avasToken rewards
     * @param tokensPerSecond How many AVA to distribute per second
     **/
    function configureRewardAsset(
        address asset,
        bool startNow,
        uint256 start,
        uint256 end,
        uint256 _totalRewardSupply, // amount to allot for avaToken
        uint256 tokensPerSecond
    ) external override {
        uint256 currentTimestamp = block.timestamp;

        require(end > currentTimestamp, "Error: End must be greather than now");

        // get balance of protocol asset
        uint256 _totalSupply = rewardsToken.balanceOf(address(this));

        // check if there is available balance
        if (_totalSupply < totalAllottedSupply) { revert("Error: No supply available"); }
        AssetData storage assetData = assetsData[asset];
        assetData.asset = asset;

        uint256 availableSupply = _totalSupply.sub(totalAllottedSupply);

        _totalRewardSupply = availableSupply < _totalRewardSupply ? availableSupply : _totalRewardSupply;
        totalAllottedSupply += _totalRewardSupply;
        assetData.totalRewardSupply = assetData.totalRewardSupply.add(_totalRewardSupply); // if already present, add
        assetData.tokensPerSecond = tokensPerSecond;
        assetData.end = end;

        // init index if new
        if (!assetData.exists) {
            assetData.exchangeRate = 1e18;
        }

        if (startNow) {
            assetData.start = currentTimestamp;
        } else if (start != 0) {
            assetData.start = start;
        }
         addAssetToList(asset);
         assetData.exists = true;

         assetData.lastUpdateTimestamp = currentTimestamp;

    }


    function addAssetToList(address asset) internal {
      uint256 _assetsCount = assetsCount;
      bool assetAlreadyAdded = false;
      for (uint256 i = 0; i < _assetsCount; i++)
          if (assetsList[i] == asset) {
              assetAlreadyAdded = true;
          }
      if (!assetAlreadyAdded) {
          assetsList[assetsCount] = asset;
          assetsCount = _assetsCount + 1;
      }

    }

    function setStart(address asset) external override {
        AssetData storage assetData = assetsData[asset];
        assetData.start = block.timestamp;
    }

    function accrueUserRewards(
        address asset,
        address user,
        uint256 previousBalance, // user
        uint256 totalTokenSupply // avaToken
    ) public override {
        AssetData storage assetData = assetsData[asset];
        if (assetData.start > block.timestamp) { return; }
        UserData storage userData = usersData[asset][user];
        uint256 accruedRewards = updateUserRewards(asset, user, previousBalance, totalTokenSupply);

        if (accruedRewards != 0) {
            _usersUnclaimedRewards[user] = _usersUnclaimedRewards[user].add(accruedRewards);
            emit RewardsAccrued(asset, user, accruedRewards);
        }
    }

    function updateUserRewards(address asset, address user, uint256 previousBalance, uint256 totalTokenSupply) internal returns (uint256) {
        AssetData storage assetData = assetsData[asset];
        UserData storage userData = usersData[asset][user];

        uint256 userIndex = userData.exchangeRate;
        uint256 accruedRewards = 0;
        uint256 newIndex = updateAssetData(assetData, totalTokenSupply);

        if (userIndex != newIndex) {
          accruedRewards = _getRewards(previousBalance, newIndex, userIndex);
          userData.exchangeRate = newIndex;
          emit UserIndexUpdated(asset, user, address(rewardsToken), newIndex);
        }

        return accruedRewards;
    }

    function updateAssetData(AssetData storage assetData, uint256 totalTokenSupply) internal returns (uint256) {
        uint256 oldIndex = assetData.exchangeRate;
        uint256 lastUpdateTimestamp = assetData.lastUpdateTimestamp;
        if (block.timestamp == lastUpdateTimestamp) {
            return oldIndex;
        }

        uint256 currentTimestamp = block.timestamp;
        uint256 timeDelta = currentTimestamp.sub(lastUpdateTimestamp);

        // update tokens released per second if reward supply left is not
        // enough
        if (
          assetData.tokensPerSecond.mul(timeDelta) > assetData.totalRewardSupply
        ) {
            assetData.tokensPerSecond = assetData.totalRewardSupply.div(timeDelta);
        }

        uint256 newIndex = calculateAssetIndex(
            assetData.tokensPerSecond,
            oldIndex,
            totalTokenSupply,
            timeDelta
        );

        if (newIndex != oldIndex) {
          assetData.exchangeRate = newIndex;
          uint256 _totalSupplyRewarded = totalTokenSupply.wadMul(newIndex.sub(oldIndex)); // total amount to be rewarded
          assetData.totalRewardSupply = assetData.totalRewardSupply.sub(_totalSupplyRewarded); // update rewardable amount

          totalSupplyRewarded += _totalSupplyRewarded; // overall

          emit AssetIndexUpdated(assetData.asset, address(rewardsToken), newIndex);
        }

        assetData.totalTokenSupply = totalTokenSupply; // update totalSupply for nxt index calcculation

        assetData.lastUpdateTimestamp = uint256(block.timestamp);

        return newIndex;
    }

    // using tokensPerSecond over interestRate because scaled totals wont be effeted
    // allows for supply to lessen and rewards end at zero
    function calculateAssetIndex(
        uint256 tokensPerSecond,
        uint256 currentIndex,
        uint256 totalSupply,
        uint256 timeDelta
    ) internal view returns (uint256) {
        if (
          tokensPerSecond == 0 ||
          totalSupply == 0 ||
          timeDelta == 0
        ) {
          return currentIndex;
        }
        uint256 currentTimestamp = block.timestamp;
        return tokensPerSecond.mul(timeDelta).mul(10**uint256(PRECISION)).div(totalSupply).add(
            currentIndex
        );

    }

    function _getRewards(
        uint256 previousBalance,
        uint256 assetIndex,
        uint256 userIndex
    ) internal pure returns (uint256) {
        return previousBalance.mul(assetIndex.sub(userIndex)).div(10**uint256(PRECISION));
    }

    function updateAssetsData(address user) internal {
        for (uint256 i = 0; i < assetsCount; i++) {
            uint256 userScaledBalance = IAvaToken(assetsList[i]).balanceOfScaled(user);
            uint256 totalTokenSupply = IAvaToken(assetsList[i]).totalScaledSupply();
            accrueUserRewards(
                assetsList[i],
                user,
                userScaledBalance,
                totalTokenSupply
            );
        }
    }

    function claimRewards(uint256 amount) external override {
        address user = msg.sender;
        updateAssetsData(user);
        uint256 userUnclaimedRewards = _usersUnclaimedRewards[user];
        if (userUnclaimedRewards == 0) {
            return;
        }
        uint256 transferAmount = amount > userUnclaimedRewards ? userUnclaimedRewards : amount;
        _usersUnclaimedRewards[user] = userUnclaimedRewards - transferAmount; // Safe due to the previous line
        rewardsToken.transfer(user, transferAmount);

        totalAllottedSupply -= transferAmount;
    }

    function getUserRewards(
        address asset,
        address user,
        uint256 previousBalance,
        uint256 tokenTotalSupply
    ) internal view returns (uint256) {
        AssetData storage assetData = assetsData[asset];
        UserData storage userData = usersData[asset][user];

        uint256 userIndex = userData.exchangeRate;
        uint256 accruedRewards = 0;
        uint256 newIndex = getAssetData(assetData, tokenTotalSupply);

        if (userIndex != newIndex) {
            accruedRewards = _getRewards(previousBalance, newIndex, userIndex);
        }

        return accruedRewards;
    }

    function getUserUnclaimedRewardsPlusAssumedRewards(address user) external view returns (uint256) {
        uint256 rewards;
        for (uint256 i = 0; i < assetsCount; i++) {
            AssetData storage assetData = assetsData[assetsList[i]];
            uint256 userScaledBalance = IAvaToken(assetsList[i]).balanceOfScaled(user);
            uint256 totalTokenSupply = IAvaToken(assetsList[i]).totalScaledSupply();
            rewards += getUserRewards(assetsList[i], user, userScaledBalance, totalTokenSupply);
        }
        return _usersUnclaimedRewards[user].add(rewards);
    }

    function getAssetData(AssetData storage assetData, uint256 tokenTotalSupply) internal view returns (uint256) {
        uint256 oldIndex = assetData.exchangeRate;
        uint256 lastUpdateTimestamp = assetData.lastUpdateTimestamp;

        if (block.timestamp == lastUpdateTimestamp) {
            return oldIndex;
        }

        uint256 timeDelta = block.timestamp.sub(lastUpdateTimestamp);

        uint256 tokensPerSecond = assetData.tokensPerSecond;
        if (assetData.tokensPerSecond.mul(timeDelta) > assetData.totalRewardSupply) {
            tokensPerSecond = assetData.totalRewardSupply.div(timeDelta);
        }

        uint256 newIndex = calculateAssetIndex(
            tokensPerSecond,
            oldIndex,
            tokenTotalSupply,
            timeDelta
        );
        return newIndex;
    }


    function getUserUnclaimedRewards(address user) external view override returns (uint256) {
        return _usersUnclaimedRewards[user];
    }

    function transferOut(address asset) external view returns (uint256) {
        AssetData storage assetData = assetsData[asset];
        require(assetData.end < block.timestamp, "Error: Rewards not ended");
    }

}
