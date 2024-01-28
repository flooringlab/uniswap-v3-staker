// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

import '@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol';
import '@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol';

/// @notice Encapsulates the logic for getting info about a NFT token ID
library NFTPositionInfo {
    struct PositionInfo {
        /// The address of the Uniswap V3 pool
        IUniswapV3Pool pool;
        /// The lower tick of the Uniswap V3 position
        int24 tickLower;
        /// The upper tick of the Uniswap V3 position
        int24 tickUpper;
        /// The amount of liquidity staked
        uint128 liquidity;
    }

    /// @param factory The address of the Uniswap V3 Factory used in computing the pool address
    /// @param nonfungiblePositionManager The address of the nonfungible position manager to query
    /// @param tokenId The unique identifier of an Uniswap V3 LP token
    /// @return positionInfo The Uniswap V3 position info
    function getPositionInfo(
        IUniswapV3Factory factory,
        INonfungiblePositionManager nonfungiblePositionManager,
        uint256 tokenId
    ) internal view returns (PositionInfo memory positionInfo) {
        address token0;
        address token1;
        uint24 fee;
        (
            ,
            ,
            token0,
            token1,
            fee,
            positionInfo.tickLower,
            positionInfo.tickUpper,
            positionInfo.liquidity,
            ,
            ,
            ,

        ) = nonfungiblePositionManager.positions(tokenId);

        positionInfo.pool = IUniswapV3Pool(
            PoolAddress.computeAddress(
                address(factory),
                PoolAddress.PoolKey({token0: token0, token1: token1, fee: fee})
            )
        );
    }
}
