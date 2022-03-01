//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IRewardsBase {

    event  RewardsAccrued(address asset, address user, uint256 accruedRewards);

    event  UserIndexUpdated(address asset, address user, address rewardsToken, uint256 newIndex);

    event  AssetIndexUpdated(address asset, address rewardsToken, uint256 newIndex);

    function configureRewardAsset(
        address asset,
        bool startNow,
        uint256 start,
        uint256 end,
        uint256 totalSupply,
        uint256 tokensPerSecond
    ) external;

    function setStart(address asset) external;

    function accrueUserRewards(
        address asset,
        address user,
        uint256 previousBalance, // user
        uint256 totalTokenSupply // avaToken
    ) external;

    function claimRewards(uint256 amount) external;

    function getUserUnclaimedRewards(address user) external view returns (uint256);
}
