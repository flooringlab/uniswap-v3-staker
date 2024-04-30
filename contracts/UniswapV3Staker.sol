// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import './interfaces/IUniswapV3Staker.sol';
import './libraries/IncentiveId.sol';
import './libraries/Oracle.sol';
import './libraries/RewardMath.sol';
import './libraries/NFTPositionInfo.sol';
import './libraries/TransferHelperExtended.sol';

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/interfaces/IERC20Minimal.sol';

import '@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import 'hardhat/console.sol';

/// @title Uniswap V3 canonical staking interface
contract UniswapV3Staker is IUniswapV3Staker, MulticallUpgradeable, UUPSUpgradeable, AccessControlUpgradeable {
    /// @notice Represents a staking incentive
    struct Incentive {
        uint256 accountedReward;
        uint256 remainingReward;
        uint256 rewardPerLiquidity;
        uint224 totalLiquidityStaked;
        uint32 lastAccrueTime;
    }

    /// @notice Represents the deposit of a liquidity NFT
    struct Deposit {
        address owner;
        uint48 numberOfStakes;
        int24 tickLower;
        int24 tickUpper;
    }

    /// @notice Represents a staked liquidity NFT
    struct Stake {
        uint256 lastRewardPerLiquidity;
        uint128 liquidity;
        uint32 stakedSince;
    }

    /// @inheritdoc IUniswapV3Staker
    IUniswapV3Factory public immutable override factory;
    /// @inheritdoc IUniswapV3Staker
    INonfungiblePositionManager public immutable override nonfungiblePositionManager;

    /// @inheritdoc IUniswapV3Staker
    uint256 public immutable override maxIncentiveStartLeadTime;
    /// @inheritdoc IUniswapV3Staker
    uint256 public immutable override maxIncentiveDuration;

    /// @inheritdoc IUniswapV3Staker
    mapping(bytes32 incentiveId => Incentive incentive) public override incentives;

    /// @inheritdoc IUniswapV3Staker
    mapping(bytes32 incentiveId => IncentiveConfig incentiveConfig) public override incentiveConfigs;

    /// @inheritdoc IUniswapV3Staker
    mapping(uint256 tokenId => Deposit deposit) public override deposits;

    /// @inheritdoc IUniswapV3Staker
    mapping(uint256 tokenId => mapping(bytes32 incentiveId => Stake stake)) public override stakes;

    /// @inheritdoc IUniswapV3Staker
    mapping(IERC20Minimal rewardToken => mapping(address owner => uint256)) public override rewards;

    /// @param _factory the Uniswap V3 factory
    /// @param _nonfungiblePositionManager the NFT position manager contract address
    /// @param _maxIncentiveStartLeadTime the max duration of an incentive in seconds
    /// @param _maxIncentiveDuration the max amount of seconds into the future the incentive startTime can be set
    constructor(
        IUniswapV3Factory _factory,
        INonfungiblePositionManager _nonfungiblePositionManager,
        uint256 _maxIncentiveStartLeadTime,
        uint256 _maxIncentiveDuration
    ) {
        factory = _factory;
        nonfungiblePositionManager = _nonfungiblePositionManager;
        maxIncentiveStartLeadTime = _maxIncentiveStartLeadTime;
        maxIncentiveDuration = _maxIncentiveDuration;

        _disableInitializers();
    }

    /// required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /// @dev just declare this as payable to reduce gas and bytecode
    function initialize() public payable initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __Multicall_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /// @inheritdoc IUniswapV3Staker
    function createIncentive(IncentiveKey memory key, IncentiveConfig memory config, uint128 reward) external override {
        if (block.timestamp > key.startTime) revert StartTimeMustBeNowOrFuture();
        if (key.startTime - block.timestamp > maxIncentiveStartLeadTime) revert StartTimeTooFarInFuture();
        if (key.startTime >= key.endTime) revert StartTimeMustBeforeEndTime();
        if (key.endTime - key.startTime > maxIncentiveDuration) revert IncentiveDurationTooLong();

        if (config.minTickWidth == 0) revert MinTickWidthMustBePositive();

        bytes32 incentiveId = IncentiveId.compute(key);
        Incentive storage incentive = incentives[incentiveId];
        if (incentive.lastAccrueTime > 0) {
            // If the incentive had been created, only creator can operate it.
            _checkRole(incentiveId);
        } else {
            if (reward <= 0) revert RewardMustBePositive();
            // Initialize the incentive.
            incentive.lastAccrueTime = uint32(key.startTime);
            _grantRole(incentiveId, _msgSender());
        }

        // Operator can add reward or update configurations after intialization.
        incentiveConfigs[incentiveId] = config;
        if (reward > 0) {
            incentive.remainingReward += reward;
            TransferHelperExtended.safeTransferFrom(address(key.rewardToken), _msgSender(), address(this), reward);
            emit IncentiveCreated(key.rewardToken, key.pool, key.startTime, key.endTime, key.refundee, reward);
        }
    }

    /// @inheritdoc IUniswapV3Staker
    function endIncentive(IncentiveKey memory key) external override returns (uint256 refund) {
        if (block.timestamp < key.endTime) revert CannotEndIncentiveBeforeEndTime();

        bytes32 incentiveId = IncentiveId.compute(key);
        Incentive storage incentive = incentives[incentiveId];

        refund = incentive.remainingReward + incentive.accountedReward;

        if (refund <= 0) revert NoRefundAvailable();
        if (incentive.totalLiquidityStaked > 0) revert CannotEndIncentiveWhileStaked();

        // issue the refund
        incentive.remainingReward = 0;
        incentive.accountedReward = 0;
        TransferHelperExtended.safeTransfer(address(key.rewardToken), key.refundee, refund);

        emit IncentiveEnded(incentiveId, refund);
    }

    /// @notice Upon receiving a Uniswap V3 ERC721, creates the token deposit setting owner to `from`. Also stakes token
    /// in one or more incentives if properly formatted `data` has a length > 0.
    /// @inheritdoc IERC721Receiver
    function onERC721Received(
        address,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        if (_msgSender() != address(nonfungiblePositionManager)) revert NotUniV3NFT();

        NFTPositionInfo.PositionInfo memory positionInfo = NFTPositionInfo.getPositionInfo(
            factory,
            nonfungiblePositionManager,
            tokenId
        );

        deposits[tokenId] = Deposit({
            owner: from,
            numberOfStakes: 0,
            tickLower: positionInfo.tickLower,
            tickUpper: positionInfo.tickUpper
        });
        emit DepositTransferred(tokenId, address(0), from);

        if (data.length > 0) {
            if (data.length == 160) {
                _stakeToken(abi.decode(data, (IncentiveKey)), tokenId, positionInfo);
            } else {
                IncentiveKey[] memory keys = abi.decode(data, (IncentiveKey[]));
                for (uint256 i = 0; i < keys.length; i++) {
                    _stakeToken(keys[i], tokenId, positionInfo);
                }
            }
        }
        return this.onERC721Received.selector;
    }

    /// @inheritdoc IUniswapV3Staker
    function transferDeposit(uint256 tokenId, address to) external override {
        if (to == address(0)) revert InvalidTransferRecipient();
        address owner = deposits[tokenId].owner;
        if (owner != _msgSender()) revert NotDepositOwner();
        deposits[tokenId].owner = to;
        emit DepositTransferred(tokenId, owner, to);
    }

    /// @inheritdoc IUniswapV3Staker
    function withdrawToken(uint256 tokenId, address to, bytes memory data) external override {
        if (to == address(this)) revert CannotWithdrawToStaker();
        Deposit memory deposit = deposits[tokenId];
        if (deposit.numberOfStakes != 0) revert CannotWithdrawWhileStaked();
        if (deposit.owner != _msgSender()) revert NotDepositOwner();

        delete deposits[tokenId];
        emit DepositTransferred(tokenId, deposit.owner, address(0));

        nonfungiblePositionManager.safeTransferFrom(address(this), to, tokenId, data);
    }

    /// @inheritdoc IUniswapV3Staker
    function stakeToken(IncentiveKey memory key, uint256 tokenId) external override {
        if (deposits[tokenId].owner != _msgSender()) revert NotDepositOwner();

        NFTPositionInfo.PositionInfo memory positionInfo = NFTPositionInfo.getPositionInfo(
            factory,
            nonfungiblePositionManager,
            tokenId
        );

        _stakeToken(key, tokenId, positionInfo);
    }

    /// @inheritdoc IUniswapV3Staker
    function unstakeToken(IncentiveKey memory key, uint256 tokenId) external override {
        Deposit memory deposit = deposits[tokenId];
        bytes32 incentiveId = IncentiveId.compute(key);
        Incentive storage incentive = incentives[incentiveId];
        Stake memory stake = stakes[tokenId][incentiveId];
        bool isLiquidation = _checkUnstakeParam(key, deposit, stake, incentiveConfigs[incentiveId]);

        _accrueReward(key, incentive);

        (uint256 ownerReward, uint256 liquidatorReward, uint256 refunded) = _computeAndDistributeReward(
            stake,
            incentiveConfigs[incentiveId],
            incentive.rewardPerLiquidity,
            isLiquidation
        );

        {
            // remove unstaked liquidity
            incentive.totalLiquidityStaked -= stake.liquidity;
            // reward is never greater than total reward unclaimed
            incentive.accountedReward -= ownerReward + liquidatorReward + refunded;
            if (refunded > 0) incentive.remainingReward += refunded;
        }
        // this only overflows if a token has a total supply greater than type(uint256).max
        if (isLiquidation) {
            rewards[key.rewardToken][deposit.owner] += ownerReward;
            rewards[key.rewardToken][_msgSender()] += liquidatorReward;
        } else {
            // liquidatorReward should be zero.
            rewards[key.rewardToken][deposit.owner] += ownerReward;
        }

        --deposits[tokenId].numberOfStakes;
        delete stakes[tokenId][incentiveId];

        emit TokenUnstaked(tokenId, incentiveId);
    }

    /// @inheritdoc IUniswapV3Staker
    function claimReward(
        IERC20Minimal rewardToken,
        address to,
        uint256 amountRequested
    ) external override returns (uint256 reward) {
        reward = rewards[rewardToken][_msgSender()];
        if (amountRequested != 0 && amountRequested < reward) {
            reward = amountRequested;
        }

        rewards[rewardToken][_msgSender()] -= reward;
        TransferHelperExtended.safeTransfer(address(rewardToken), to, reward);

        emit RewardClaimed(to, reward);
    }

    /// @inheritdoc IUniswapV3Staker
    function getRewardInfo(
        IncentiveKey memory key,
        uint256 tokenId
    )
        external
        view
        override
        returns (uint256 ownerReward, uint256 liquidatorReward, uint256 refunded, uint256 currentRewardPerLiquidity)
    {
        bytes32 incentiveId = IncentiveId.compute(key);

        Stake memory stake = stakes[tokenId][incentiveId];
        if (stake.liquidity <= 0) revert StakeNotExist();

        Incentive memory incentive = incentives[incentiveId];

        (currentRewardPerLiquidity, ) = RewardMath.computeRewardPerLiquidityDiff(
            incentive.remainingReward,
            incentive.totalLiquidityStaked,
            key.endTime,
            incentive.lastAccrueTime,
            block.timestamp
        );
        currentRewardPerLiquidity += incentive.rewardPerLiquidity;

        Deposit memory deposit = deposits[tokenId];
        (ownerReward, liquidatorReward, refunded) = _computeAndDistributeReward(
            stake,
            incentiveConfigs[incentiveId],
            currentRewardPerLiquidity,
            !_isPositionInRange(
                key.pool,
                deposit.tickLower,
                deposit.tickUpper,
                incentiveConfigs[incentiveId].twapSeconds
            )
        );
    }

    /// @dev Stakes a deposited token without doing an ownership check
    function _stakeToken(
        IncentiveKey memory key,
        uint256 tokenId,
        NFTPositionInfo.PositionInfo memory positionInfo
    ) private {
        if (block.timestamp < key.startTime) revert IncentiveNotStarted();
        if (block.timestamp >= key.endTime) revert IncentiveWasEnded();

        bytes32 incentiveId = IncentiveId.compute(key);

        if (incentives[incentiveId].remainingReward <= 0) revert IncentiveNotExist();
        if (stakes[tokenId][incentiveId].liquidity != 0) revert TokenAlreadyStaked();

        (IUniswapV3Pool pool, int24 tickLower, int24 tickUpper, uint128 liquidity) = (
            positionInfo.pool,
            positionInfo.tickLower,
            positionInfo.tickUpper,
            positionInfo.liquidity
        );

        {
            IncentiveConfig memory incentiveConfig = incentiveConfigs[incentiveId];
            if (pool != key.pool) revert PoolNotMatched();
            if (positionInfo.liquidity == 0) revert CannotStakeZeroLiquidity();
            if (incentiveConfig.minTickWidth > uint24(tickUpper - tickLower)) revert PositionRangeTooNarrow();
            /// Position should include current tick
            if (!_isPositionInRange(pool, tickLower, tickUpper, 0)) revert CurrentTickMustWithinRange();
        }

        Incentive storage incentive = incentives[incentiveId];
        _accrueReward(key, incentive);

        stakes[tokenId][incentiveId] = Stake({
            stakedSince: uint32(block.timestamp),
            liquidity: liquidity,
            lastRewardPerLiquidity: incentive.rewardPerLiquidity
        });

        incentive.totalLiquidityStaked += liquidity;
        ++deposits[tokenId].numberOfStakes;

        emit TokenStaked(tokenId, incentiveId, liquidity);
    }

    function _accrueReward(IncentiveKey memory key, Incentive storage incentive) private {
        /// accrue previous rewards
        (uint256 rewardPerLiquidityDiff, uint256 accruedReward) = RewardMath.computeRewardPerLiquidityDiff(
            incentive.remainingReward,
            incentive.totalLiquidityStaked,
            key.endTime,
            incentive.lastAccrueTime,
            block.timestamp
        );

        if (accruedReward > 0) {
            incentive.accountedReward += accruedReward;
            incentive.remainingReward -= accruedReward;
            // accumulate reward for per share
            incentive.rewardPerLiquidity += rewardPerLiquidityDiff;
        }

        // update the last accural time
        incentive.lastAccrueTime = uint32(Math.min(block.timestamp, key.endTime));
    }

    function _computeAndDistributeReward(
        Stake memory stake,
        IncentiveConfig memory incentiveConfig,
        uint256 currentRewardPerLiquidity,
        bool isLiquidation
    ) private view returns (uint256, uint256, uint256) {
        uint256 reward = RewardMath.computeRewardAmount(
            stake.liquidity,
            stake.lastRewardPerLiquidity,
            currentRewardPerLiquidity
        );

        return
            isLiquidation
                ? RewardMath.computeRewardDistribution(
                    reward,
                    stake.stakedSince,
                    block.timestamp,
                    incentiveConfig.penaltyDecayPeriod,
                    incentiveConfig.minPenaltyBips,
                    incentiveConfig.liquidationBonusBips
                )
                : (reward, 0, 0);
    }

    function _checkUnstakeParam(
        IncentiveKey memory key,
        Deposit memory deposit,
        Stake memory stake,
        IncentiveConfig memory incentiveConfig
    ) private view returns (bool) {
        if (stake.liquidity <= 0) revert StakeNotExist();

        bool isLiquidation = false;
        if (block.timestamp < key.endTime) {
            bool inRange = _isPositionInRange(
                key.pool,
                deposit.tickLower,
                deposit.tickUpper,
                incentiveConfig.twapSeconds
            );
            if (inRange && _msgSender() != deposit.owner) revert CannotLiquidateWhileActive();

            // active liquidity requires a minimum staking duration for exiting
            if (inRange && (block.timestamp - stake.stakedSince) < incentiveConfig.minExitDuration)
                revert UnstakeRequireMinDuration();

            isLiquidation = !inRange;
        }

        // Any EOA accounts can liquidate the stakes that are out of range
        // prevent price manipulation using Flash Loan or something else
        if (isLiquidation && _msgSender() != tx.origin) revert CannotLiquidateByContract();

        return isLiquidation;
    }

    function _isPositionInRange(
        IUniswapV3Pool pool,
        int24 tickLower,
        int24 tickUpper,
        uint32 twapSeconds
    ) private view returns (bool) {
        int24 tick;
        if (twapSeconds == 0) {
            (, tick, , , , , ) = pool.slot0();
        } else {
            tick = Oracle.consult(pool, twapSeconds);
        }
        return tickLower <= tick && tick <= tickUpper;
    }
}
