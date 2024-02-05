// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/interfaces/IERC20Minimal.sol';
import '@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol';

/// @title Uniswap V3 Staker Interface
/// @notice Allows staking nonfungible liquidity tokens in exchange for reward tokens
interface IUniswapV3Staker is IERC721Receiver {
    /// @param rewardToken The token being distributed as a reward
    /// @param pool The Uniswap V3 pool
    /// @param startTime The time when the incentive program begins
    /// @param endTime The time when rewards stop accruing
    /// @param refundee The address which receives any remaining reward tokens when the incentive is ended
    struct IncentiveKey {
        IERC20Minimal rewardToken;
        IUniswapV3Pool pool;
        uint256 startTime;
        uint256 endTime;
        address refundee;
    }

    /// @param minTickWidth The minimum width that staked positions should be kept
    /// @param penaltyDecayPeriod The period over which the penalty for liquidation decays
    /// @param minPenaltyBips The minimum penalty as a percentage of the reward when liquidating
    /// @param minExitDuration The minimum duration for which staked positions should be kept
    /// @param liquidationBonusBips The bonus as a percentage of the reward for liquidators
    struct IncentiveConfig {
        uint24 minTickWidth;
        uint32 penaltyDecayPeriod;
        uint16 minPenaltyBips;
        uint32 minExitDuration;
        uint16 liquidationBonusBips;
    }

    /// @notice The Uniswap V3 Factory
    function factory() external view returns (IUniswapV3Factory);

    /// @notice The nonfungible position manager with which this staking contract is compatible
    function nonfungiblePositionManager() external view returns (INonfungiblePositionManager);

    /// @notice The max duration of an incentive in seconds
    function maxIncentiveDuration() external view returns (uint256);

    /// @notice The max amount of seconds into the future the incentive startTime can be set
    function maxIncentiveStartLeadTime() external view returns (uint256);

    /// @notice Represents a staking incentive
    /// @param incentiveId The ID of the incentive computed from its parameters
    /// @return remainingReward The amount of reward token not yet claimed by users
    /// @return accountedReward The amount of reward token not yet claimed by users
    /// @return rewardPerShare Accumulated reward Per share
    /// @return totalLiquidityStaked Total liquidity staked
    /// @return lastAccrueTime Last time rewardPerShare was updated
    function incentives(
        bytes32 incentiveId
    )
        external
        view
        returns (
            uint128 remainingReward,
            uint128 accountedReward,
            uint256 rewardPerShare,
            uint224 totalLiquidityStaked,
            uint32 lastAccrueTime
        );

    /// @notice Represents a staking incentive config
    /// @param incentiveId The ID of the incentive computed from its parameters
    function incentiveConfigs(
        bytes32 incentiveId
    )
        external
        view
        returns (
            uint24 minTickWidth,
            uint32 penaltyDecayPeriod,
            uint16 minPenaltyBips,
            uint32 minExitDuration,
            uint16 liquidationBonusBips
        );

    /// @notice Returns information about a deposited NFT
    /// @return owner The owner of the deposited NFT
    /// @return numberOfStakes Counter of how many incentives for which the liquidity is staked
    /// @return tickLower The lower tick of the range
    /// @return tickUpper The upper tick of the range
    function deposits(
        uint256 tokenId
    ) external view returns (address owner, uint48 numberOfStakes, int24 tickLower, int24 tickUpper);

    /// @notice Returns information about a staked liquidity NFT
    /// @param tokenId The ID of the staked token
    /// @param incentiveId The ID of the incentive for which the token is staked
    /// @return lastRewardPerShare The last `rewardPerShare` used to calculate the reward of the `tokenId`
    /// @return liquidity The amount of liquidity in the NFT
    /// @return stakedSince The timestamp indicating when the token was staked
    function stakes(
        uint256 tokenId,
        bytes32 incentiveId
    ) external view returns (uint256 lastRewardPerShare, uint128 liquidity, uint32 stakedSince);

    /// @notice Returns amounts of reward tokens owed to a given address according to the last time all stakes were updated
    /// @param rewardToken The token for which to check rewards
    /// @param owner The owner for which the rewards owed are checked
    /// @return rewardsOwed The amount of the reward token claimable by the owner
    function rewards(IERC20Minimal rewardToken, address owner) external view returns (uint256 rewardsOwed);

    /// @notice Creates a new liquidity mining incentive program
    /// @param key Details of the incentive to create
    /// @param config Config of the incentive to create
    /// @param reward The amount of reward tokens to be distributed
    function createIncentive(IncentiveKey memory key, IncentiveConfig memory config, uint128 reward) external;

    /// @notice Ends an incentive after the incentive end time has passed and all stakes have been withdrawn
    /// @param key Details of the incentive to end
    /// @return refund The remaining reward tokens when the incentive is ended
    function endIncentive(IncentiveKey memory key) external returns (uint256 refund);

    function setIncentiveConfig(bytes32 incentiveId, IncentiveConfig memory config) external;

    /// @notice Transfers ownership of a deposit from the sender to the given recipient
    /// @param tokenId The ID of the token (and the deposit) to transfer
    /// @param to The new owner of the deposit
    function transferDeposit(uint256 tokenId, address to) external;

    /// @notice Withdraws a Uniswap V3 LP token `tokenId` from this contract to the recipient `to`
    /// @param tokenId The unique identifier of an Uniswap V3 LP token
    /// @param to The address where the LP token will be sent
    /// @param data An optional data array that will be passed along to the `to` address via the NFT safeTransferFrom
    function withdrawToken(uint256 tokenId, address to, bytes memory data) external;

    /// @notice Stakes a Uniswap V3 LP token
    /// @param key The key of the incentive for which to stake the NFT
    /// @param tokenId The ID of the token to stake
    function stakeToken(IncentiveKey memory key, uint256 tokenId) external;

    /// @notice Unstakes a Uniswap V3 LP token
    /// @param key The key of the incentive for which to unstake the NFT
    /// @param tokenId The ID of the token to unstake
    function unstakeToken(
        IncentiveKey memory key,
        uint256 tokenId
    ) external returns (uint256 liquidatorEarning, uint256 ownerEarning, uint256 refunded);

    /// @notice Transfers `amountRequested` of accrued `rewardToken` rewards from the contract to the recipient `to`
    /// @param rewardToken The token being distributed as a reward
    /// @param to The address where claimed rewards will be sent to
    /// @param amountRequested The amount of reward tokens to claim. Claims entire reward amount if set to 0.
    /// @return reward The amount of reward tokens claimed
    function claimReward(
        IERC20Minimal rewardToken,
        address to,
        uint256 amountRequested
    ) external returns (uint256 reward);

    /// @notice Calculates the reward amount that will be received for the given stake
    /// @param key The key of the incentive
    /// @param tokenId The ID of the token
    /// @return reward The reward accrued to the NFT for the given incentive thus far
    /// @return currentRewardPerLiquidity current reward per share to compute the reward
    function getRewardInfo(
        IncentiveKey memory key,
        uint256 tokenId
    ) external returns (uint256 reward, uint256 currentRewardPerLiquidity);

    /// @notice Event emitted when a liquidity mining incentive has been created
    /// @param rewardToken The token being distributed as a reward
    /// @param pool The Uniswap V3 pool
    /// @param startTime The time when the incentive program begins
    /// @param endTime The time when rewards stop accruing
    /// @param refundee The address which receives any remaining reward tokens after the end time
    /// @param reward The amount of reward tokens to be distributed
    event IncentiveCreated(
        IERC20Minimal indexed rewardToken,
        IUniswapV3Pool indexed pool,
        uint256 startTime,
        uint256 endTime,
        address refundee,
        uint256 reward
    );

    /// @notice Event that can be emitted when a liquidity mining incentive has ended
    /// @param incentiveId The incentive which is ending
    /// @param refund The amount of reward tokens refunded
    event IncentiveEnded(bytes32 indexed incentiveId, uint256 refund);

    /// @notice Emitted when ownership of a deposit changes
    /// @param tokenId The ID of the deposit (and token) that is being transferred
    /// @param oldOwner The owner before the deposit was transferred
    /// @param newOwner The owner after the deposit was transferred
    event DepositTransferred(uint256 indexed tokenId, address indexed oldOwner, address indexed newOwner);

    /// @notice Event emitted when a Uniswap V3 LP token has been staked
    /// @param tokenId The unique identifier of an Uniswap V3 LP token
    /// @param liquidity The amount of liquidity staked
    /// @param incentiveId The incentive in which the token is staking
    event TokenStaked(uint256 indexed tokenId, bytes32 indexed incentiveId, uint128 liquidity);

    /// @notice Event emitted when a Uniswap V3 LP token has been unstaked
    /// @param tokenId The unique identifier of an Uniswap V3 LP token
    /// @param incentiveId The incentive in which the token is staking
    event TokenUnstaked(uint256 indexed tokenId, bytes32 indexed incentiveId);

    /// @notice Event emitted when a reward token has been claimed
    /// @param to The address where claimed rewards were sent to
    /// @param reward The amount of reward tokens claimed
    event RewardClaimed(address indexed to, uint256 reward);

    error RewardMustBePositive();
    error StartTimeMustBeNowOrFuture();
    error StartTimeTooFarInFuture();
    error StartTimeMustBeforeEndTime();
    error IncentiveDurationTooLong();
    error MinTickWidthMustBePositive();

    error CannotEndIncentiveBeforeEndTime();
    error NoRefundAvailable();
    error CannotEndIncentiveWhileStaked();

    error NotUniV3NFT();
    error InvalidTransferRecipient();
    error NotDepositOwner();
    error CannotWithdrawToStaker();
    error CannotWithdrawWhileStaked();

    error CannotLiquidateByContract();
    error CannotLiquidateWhileActive();
    error UnstakeRequireMinDuration();

    error StakeNotExist();
    error IncentiveNotStarted();
    error IncentiveWasEnded();
    error IncentiveNotExist();
    error TokenAlreadyStaked();
    error PoolNotMatched();
    error CannotStakeZeroLiquidity();
    error PositionRangeTooNarrow();
    error CurrentTickMustWithinRange();
}
