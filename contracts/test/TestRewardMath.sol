// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import '../interfaces/IUniswapV3Staker.sol';

import '../libraries/RewardMath.sol';

/// @dev Test contract for RewardMatrh
contract TestRewardMath {
    function computeRewardPerShareDiff(
        uint256 remainingReward,
        uint256 totalShares,
        uint256 endTime,
        uint256 lastAccrueTime,
        uint256 currentTime
    ) internal pure returns (uint256 rewardPerShareDiff) {
        rewardPerShareDiff = RewardMath.computeRewardPerShareDiff(
            remainingReward,
            totalShares,
            endTime,
            lastAccrueTime,
            currentTime
        );
    }

    function computeRewardDistribution(
        uint256 reward,
        uint32 stakedSince,
        uint32 penaltyDecreasePeriod
    ) internal view returns (uint256 ownerEarning, uint256 liquidatorEarning, uint256 refunded) {
        (ownerEarning, liquidatorEarning, refunded) = RewardMath.computeRewardDistribution(
            reward,
            stakedSince,
            penaltyDecreasePeriod
        );
    }
}
