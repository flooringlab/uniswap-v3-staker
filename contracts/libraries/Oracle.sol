// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

/// @title Oracle library
/// @author Copied from https://github.com/Uniswap/v3-periphery/blob/0.8/contracts/libraries/OracleLibrary.sol
/// @notice Provides functions to integrate with V3 pool oracle
library Oracle {
    /// @notice Calculates time-weighted means of tick and liquidity for a given Uniswap V3 pool
    /// @param pool Address of the pool that we want to observe
    /// @param secondsAgo Number of seconds in the past from which to calculate the time-weighted means
    /// @return arithmeticMeanTick The arithmetic mean tick from (block.timestamp - secondsAgo) to block.timestamp
    function consult(IUniswapV3Pool pool, uint32 secondsAgo) internal view returns (int24 arithmeticMeanTick) {
        require(secondsAgo != 0, 'BP');

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives, ) = pool.observe(secondsAgos);

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        arithmeticMeanTick = int24(tickCumulativesDelta / int56(uint56(secondsAgo)));
        // Always round to negative infinity
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(uint56(secondsAgo)) != 0)) arithmeticMeanTick--;
    }
}
