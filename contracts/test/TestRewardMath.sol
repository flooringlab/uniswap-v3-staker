// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import '../interfaces/IUniswapV3Staker.sol';

import '../libraries/RewardMath.sol';

/// @dev Test contract for RewardMatrh
contract TestRewardMath {
    function computeRewardAmount(
        uint256 shares,
        uint256 lastRewardPerShare,
        uint256 currentRewardPerShare
    ) public pure returns (uint256 reward) {
        reward = RewardMath.computeRewardAmount(shares, lastRewardPerShare, currentRewardPerShare);
    }

    function computeRewardPerShareDiff(
        uint256 remainingReward,
        uint256 totalShares,
        uint256 endTime,
        uint256 lastAccrueTime,
        uint256 currentTime
    ) public pure returns (uint256 rewardPerShareDiff, uint256 accruedReward) {
        return RewardMath.computeRewardPerShareDiff(remainingReward, totalShares, endTime, lastAccrueTime, currentTime);
    }

    function computeRewardDistribution(
        uint256 reward,
        uint256 stakedSince,
        uint256 currentTime,
        uint256 penaltyDecayPeriod,
        uint256 minPenaltyBips,
        uint256 liquidationBonusBips
    ) public pure returns (uint256 ownerEarning, uint256 liquidatorEarning, uint256 refunded) {
        (ownerEarning, liquidatorEarning, refunded) = RewardMath.computeRewardDistribution(
            reward,
            stakedSince,
            currentTime,
            penaltyDecayPeriod,
            minPenaltyBips,
            liquidationBonusBips
        );
    }
}
