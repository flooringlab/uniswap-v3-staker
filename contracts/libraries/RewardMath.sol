// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import '@uniswap/v3-core/contracts/libraries/FullMath.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';

/// @title Math for computing rewards
/// @notice Allows computing rewards given some parameters of stakes and incentives
library RewardMath {
    function computeRewardPerShareDiff(
        uint256 remainingReward,
        uint256 totalShares,
        uint256 endTime,
        uint256 lastAccrueTime,
        uint256 currentTime
    ) internal pure returns (uint256 rewardPerShareDiff) {
        uint256 accruedReward = FullMath.mulDiv(
            remainingReward,
            (currentTime - lastAccrueTime),
            (endTime - lastAccrueTime)
        );

        return accruedReward / totalShares;
    }

    function computeRewardDistribution(
        uint256 reward,
        uint256 stakedSince,
        uint256 currentTime,
        uint256 penaltyDecayPeriod,
        uint256 minPenaltyBips
    ) internal pure returns (uint256 ownerEarning, uint256 liquidatorEarning, uint256 refunded) {
        uint256 timeElapsed = currentTime - stakedSince;

        // Initial decay, right shift operation simulates exponential decay by dividing by 2^n
        uint256 penalty = reward >> (timeElapsed / penaltyDecayPeriod);

        // Calculate the remaining time after the half-life period
        timeElapsed %= penaltyDecayPeriod;

        // Simulate linear decay for the part not covered by exponential decay
        penalty = penalty - (FullMath.mulDiv(penalty, timeElapsed, penaltyDecayPeriod) >> 1);

        // Ensure penalty is at least minPenaltyBips percentage of the reward
        penalty = Math.max(penalty, FullMath.mulDiv(reward, minPenaltyBips, 10000));

        // Calculate liquidatorEarning, refunded, and ownerEarning
        liquidatorEarning = penalty / 2;
        refunded = penalty - liquidatorEarning;
        ownerEarning = reward - penalty;
    }
}
