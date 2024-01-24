// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;
pragma abicoder v2;

import '../interfaces/IUniswapV3Staker.sol';

import '../libraries/RewardMath.sol';

/// @dev Test contract for RewardMatrh
contract TestRewardMath {
    function computeRewardAmount(
        uint256 totalRewardUnclaimed,
        uint160 totalSecondsClaimedX128,
        uint256 startTime,
        uint256 endTime,
        uint128 liquidity,
        uint160 secondsPerLiquidityInsideInitialX128,
        uint160 secondsPerLiquidityInsideX128,
        uint32 stakedSince,
        uint256 currentTime
    ) public pure returns (uint256 reward, uint160 secondsInsideX128) {
        (reward, secondsInsideX128) = RewardMath.computeRewardAmount(
            totalRewardUnclaimed,
            totalSecondsClaimedX128,
            startTime,
            endTime,
            liquidity,
            secondsPerLiquidityInsideInitialX128,
            secondsPerLiquidityInsideX128,
            stakedSince,
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
