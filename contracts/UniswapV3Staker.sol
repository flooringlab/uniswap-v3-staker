// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import './interfaces/IUniswapV3Staker.sol';
import './libraries/IncentiveId.sol';
import './libraries/RewardMath.sol';
import './libraries/NFTPositionInfo.sol';
import './libraries/TransferHelperExtended.sol';

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/interfaces/IERC20Minimal.sol';

import '@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol';

import '@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

/// @title Uniswap V3 canonical staking interface
contract UniswapV3Staker is IUniswapV3Staker, MulticallUpgradeable, UUPSUpgradeable, OwnableUpgradeable {
    /// @notice Represents a staking incentive
    struct Incentive {
        uint256 remainingReward;
        uint256 totalShares;
        uint256 rewardPerShare;
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
        uint256 lastRewardPerShare;
        uint128 shares;
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

    /// @dev bytes32 refers to the return value of IncentiveId.compute
    mapping(bytes32 => Incentive) public override incentives;

    /// @dev deposits[tokenId] => Deposit
    mapping(uint256 => Deposit) public override deposits;

    /// @dev stakes[tokenId][incentiveHash] => Stake
    mapping(uint256 => mapping(bytes32 => Stake)) public override stakes;

    /// @dev rewards[rewardToken][owner] => uint256
    /// @inheritdoc IUniswapV3Staker
    mapping(IERC20Minimal => mapping(address => uint256)) public override rewards;

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
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @dev just declare this as payable to reduce gas and bytecode
    function initialize() public payable initializer {
        __Ownable_init(_msgSender());
        __UUPSUpgradeable_init();
        __Multicall_init();
    }

    /// @inheritdoc IUniswapV3Staker
    function createIncentive(IncentiveKey memory key, uint256 reward) external override {
        if (reward <= 0) revert RewardMustBePositive();
        if (block.timestamp > key.startTime) revert StartTimeMustBeNowOrFuture();
        if (key.startTime - block.timestamp > maxIncentiveStartLeadTime) revert StartTimeTooFarInFuture();
        if (key.startTime >= key.endTime) revert StartTimeMustBeforeEndTime();
        if (key.endTime - key.startTime > maxIncentiveDuration) revert IncentiveDurationTooLong();
        if (key.minTickWidth == 0) revert MinTickWidthMustBePositive();

        bytes32 incentiveId = IncentiveId.compute(key);

        incentives[incentiveId].remainingReward += reward;
        incentives[incentiveId].lastAccrueTime = uint32(block.timestamp);

        TransferHelperExtended.safeTransferFrom(address(key.rewardToken), msg.sender, address(this), reward);

        emit IncentiveCreated(key.rewardToken, key.pool, key.startTime, key.endTime, key.refundee, reward);
    }

    /// @inheritdoc IUniswapV3Staker
    function endIncentive(IncentiveKey memory key) external override returns (uint256 refund) {
        if (block.timestamp < key.endTime) revert CannotEndIncentiveBeforeEndTime();

        bytes32 incentiveId = IncentiveId.compute(key);
        Incentive storage incentive = incentives[incentiveId];

        refund = incentive.remainingReward;

        if (refund <= 0) revert NoRefundAvailable();
        if (incentive.totalShares > 0) revert CannotEndIncentiveWhileStaked();

        // issue the refund
        incentive.remainingReward = 0;
        TransferHelperExtended.safeTransfer(address(key.rewardToken), key.refundee, refund);

        // note we never clear totalSecondsClaimedX128

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
    function unstakeToken(
        IncentiveKey memory key,
        uint256 tokenId
    ) external override returns (uint256, uint256, uint256) {
        Deposit memory deposit = deposits[tokenId];

        bool isLiquidation = false;
        if (block.timestamp < key.endTime) {
            (, int24 tick, , , , , ) = key.pool.slot0();
            bool inRange = deposit.tickLower <= tick && tick <= deposit.tickUpper;
            if (inRange && _msgSender() != deposit.owner) revert CannotLiquidateWhileActive();

            isLiquidation = !inRange;
        }

        // Anyone(except Contract Caller) can liquidate the stakes that are out of range
        // prevent price manipulation using Flash Loan or something else
        if (isLiquidation && _msgSender().code.length > 0) revert CannotLiquidateByContract();

        bytes32 incentiveId = IncentiveId.compute(key);
        Incentive storage incentive = incentives[incentiveId];
        _accrueReward(key, incentive);

        Stake storage stake = stakes[tokenId][incentiveId];
        uint256 reward = stake.shares * (incentive.rewardPerShare - stake.lastRewardPerShare);

        (uint256 ownerEarning, uint256 liquidatorEarning, ) = isLiquidation
            ? RewardMath.computeRewardDistribution(reward, stake.stakedSince, key.penaltyDecreasePeriod)
            : (reward, 0, 0);

        --deposits[tokenId].numberOfStakes;

        incentive.totalShares -= stake.shares;
        // reward is never greater than total reward unclaimed
        incentive.remainingReward -= (ownerEarning + liquidatorEarning);
        // this only overflows if a token has a total supply greater than type(uint256).max
        if (isLiquidation) {
            rewards[key.rewardToken][deposit.owner] += ownerEarning;
            rewards[key.rewardToken][_msgSender()] += liquidatorEarning;
        } else {
            rewards[key.rewardToken][deposit.owner] += ownerEarning + liquidatorEarning;
        }

        delete stakes[tokenId][incentiveId];

        return (liquidatorEarning, ownerEarning, reward - ownerEarning - liquidatorEarning);
    }

    /// @inheritdoc IUniswapV3Staker
    function claimReward(
        IERC20Minimal rewardToken,
        address to,
        uint256 amountRequested
    ) external override returns (uint256 reward) {
        reward = rewards[rewardToken][msg.sender];
        if (amountRequested != 0 && amountRequested < reward) {
            reward = amountRequested;
        }

        rewards[rewardToken][msg.sender] -= reward;
        TransferHelperExtended.safeTransfer(address(rewardToken), to, reward);

        emit RewardClaimed(to, reward);
    }

    /// @inheritdoc IUniswapV3Staker
    function getRewardInfo(
        IncentiveKey memory key,
        uint256 tokenId
    ) external view override returns (uint256 reward, uint256 currentRewardPerShare) {
        bytes32 incentiveId = IncentiveId.compute(key);

        Stake memory stake = stakes[tokenId][incentiveId];
        if (stake.shares <= 0) revert StakeNotExist();

        Incentive memory incentive = incentives[incentiveId];

        currentRewardPerShare =
            incentive.rewardPerShare +
            RewardMath.computeRewardPerShareDiff(
                incentive.remainingReward,
                incentive.totalShares,
                key.endTime,
                incentive.lastAccrueTime,
                block.timestamp
            );

        reward = stake.shares * (currentRewardPerShare - stake.lastRewardPerShare);
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
        if (stakes[tokenId][incentiveId].shares != 0) revert TokenAlreadyStaked();

        (IUniswapV3Pool pool, int24 tickLower, int24 tickUpper, uint128 liquidity) = (
            positionInfo.pool,
            positionInfo.tickLower,
            positionInfo.tickUpper,
            positionInfo.liquidity
        );

        {
            if (pool != key.pool) revert PoolNotMatched();
            if (positionInfo.liquidity == 0) revert CannotStakeZeroLiquidity();
            if (key.minTickWidth > uint24(tickUpper - tickLower)) revert PositionRangeTooNarrow();
            /// Position should include current tick
            (, int24 tick, , , , , ) = pool.slot0();
            if (tick < tickLower || tick > tickUpper) revert CurrentTickMustWithinRange();
        }

        Incentive storage incentive = incentives[incentiveId];
        _accrueReward(key, incentive);

        stakes[tokenId][incentiveId] = Stake({
            stakedSince: uint32(block.timestamp),
            shares: liquidity,
            lastRewardPerShare: incentive.rewardPerShare
        });

        incentive.totalShares += liquidity;
        deposits[tokenId].numberOfStakes++;

        emit TokenStaked(tokenId, incentiveId, liquidity);
    }

    function _accrueReward(IncentiveKey memory key, Incentive storage incentive) private {
        /// accrue previous rewards
        incentive.rewardPerShare += RewardMath.computeRewardPerShareDiff(
            incentive.remainingReward,
            incentive.totalShares,
            key.endTime,
            incentive.lastAccrueTime,
            block.timestamp
        );
        // update the last accural time
        incentive.lastAccrueTime = uint32(block.timestamp);
    }
}
