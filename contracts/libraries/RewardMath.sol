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
        uint32 stakedSince,
        uint32 penaltyDecreasePeriod
    ) internal view returns (uint256 ownerEarning, uint256 liquidatorEarning, uint256 refunded) {
        /// penalty decreases exponentially
        uint256 penalty = reward /
            (2 ** ((block.timestamp - stakedSince + penaltyDecreasePeriod - 1) / penaltyDecreasePeriod));
        liquidatorEarning = penalty / 2;
        refunded = penalty - liquidatorEarning;
        ownerEarning = reward - penalty;
    }
}
