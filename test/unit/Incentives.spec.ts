import { LoadFixtureFunction } from '../types'
import { uniswapFixture, UniswapFixtureType } from '../shared/fixtures'
import {
  expect,
  getMaxTick,
  getMinTick,
  FeeAmount,
  TICK_SPACINGS,
  blockTimestamp,
  BN,
  BNe18,
  snapshotGasCost,
  ActorFixture,
  erc20Wrap,
  makeTimestamps,
  defaultIncentiveCfg,
} from '../shared'
import { createFixtureLoader, provider } from '../shared/provider'
import { HelperCommands, ERC20Helper } from '../helpers'
import { ContractParams } from '../../types/contractParams'
import { createTimeMachine } from '../shared/time'
import { HelperTypes } from '../helpers/types'

let loadFixture: LoadFixtureFunction

describe('unit/Incentives', async () => {
  const actors = new ActorFixture(provider.getWallets(), provider)
  const incentiveCreator = actors.incentiveCreator()
  const totalReward = BNe18(100)
  const erc20Helper = new ERC20Helper()
  const Time = createTimeMachine(provider)

  let helpers: HelperCommands
  let context: UniswapFixtureType
  let timestamps: ContractParams.Timestamps

  before('loader', async () => {
    loadFixture = createFixtureLoader(provider.getWallets(), provider)
  })

  beforeEach('create fixture loader', async () => {
    context = await loadFixture(uniswapFixture)
    helpers = HelperCommands.fromTestContext(context, actors, provider)
  })

  describe('#createIncentive', () => {
    let subject: (params: Partial<ContractParams.CreateIncentive>) => Promise<any>

    beforeEach('setup', async () => {
      subject = async (params: Partial<ContractParams.CreateIncentive> = {}) => {
        await erc20Helper.ensureBalancesAndApprovals(
          incentiveCreator,
          params.rewardToken ? await erc20Wrap(params?.rewardToken) : context.rewardToken,
          totalReward,
          context.staker.address,
        )

        const { startTime, endTime } = makeTimestamps(await blockTimestamp())

        return await context.staker.connect(incentiveCreator).createIncentive(
          {
            rewardToken: params.rewardToken || context.rewardToken.address,
            pool: context.pool01,
            startTime: params.startTime || startTime,
            endTime: params.endTime || endTime,
            refundee: params.refundee || incentiveCreator.address,
          },
          defaultIncentiveCfg(),
          totalReward,
        )
      }
    })

    describe('works and', () => {
      it('transfers the right amount of rewardToken', async () => {
        const balanceBefore = await context.rewardToken.balanceOf(context.staker.address)
        await subject({
          reward: totalReward,
          rewardToken: context.rewardToken.address,
        })
        expect(await context.rewardToken.balanceOf(context.staker.address)).to.eq(balanceBefore.add(totalReward))
      })

      it('emits an event with valid parameters', async () => {
        const { startTime, endTime } = makeTimestamps(await blockTimestamp())
        await expect(subject({ startTime, endTime }))
          .to.emit(context.staker, 'IncentiveCreated')
          .withArgs(
            context.rewardToken.address,
            context.pool01,
            startTime,
            endTime,
            incentiveCreator.address,
            totalReward,
          )
      })

      it('creates an incentive with the correct parameters', async () => {
        timestamps = makeTimestamps(await blockTimestamp())
        await subject(timestamps)
        const incentiveId = await context.testIncentiveId.compute({
          rewardToken: context.rewardToken.address,
          pool: context.pool01,
          startTime: timestamps.startTime,
          endTime: timestamps.endTime,
          refundee: incentiveCreator.address,
        })

        const incentive = await context.staker.incentives(incentiveId)
        expect(incentive.remainingReward).to.equal(totalReward)
        expect(incentive.rewardPerLiquidity).to.equal(BN(0))
      })

      it('adds to existing incentives', async () => {
        const params = makeTimestamps(await blockTimestamp())
        expect(await subject(params)).to.emit(context.staker, 'IncentiveCreated')
        await expect(subject(params)).to.not.be.reverted
        const incentiveId = await context.testIncentiveId.compute({
          rewardToken: context.rewardToken.address,
          pool: context.pool01,
          startTime: timestamps.startTime,
          endTime: timestamps.endTime,
          refundee: incentiveCreator.address,
        })
        const { remainingReward, rewardPerLiquidity, totalLiquidityStaked } =
          await context.staker.incentives(incentiveId)
        expect(remainingReward).to.equal(totalReward.mul(2))
        expect(rewardPerLiquidity).to.equal(0)
        expect(totalLiquidityStaked).to.equal(0)
      })

      it('does not override the existing numberOfStakes', async () => {
        const testTimestamps = makeTimestamps(await blockTimestamp())
        const rewardToken = context.token0
        const incentiveKey = {
          ...testTimestamps,
          rewardToken: rewardToken.address,
          refundee: incentiveCreator.address,
          pool: context.pool01,
        }
        await erc20Helper.ensureBalancesAndApprovals(actors.lpUser0(), rewardToken, BN(100), context.staker.address)
        await context.staker.connect(actors.lpUser0()).createIncentive(incentiveKey, defaultIncentiveCfg(), 100)
        const incentiveId = await context.testIncentiveId.compute(incentiveKey)
        let { remainingReward, rewardPerLiquidity, totalLiquidityStaked } = await context.staker.incentives(incentiveId)
        expect(remainingReward).to.equal(100)
        expect(rewardPerLiquidity).to.equal(0)
        expect(totalLiquidityStaked).to.equal(0)
        expect(await rewardToken.balanceOf(context.staker.address)).to.eq(100)
        const { tokenId } = await helpers.mintFlow({
          lp: actors.lpUser0(),
          tokens: [context.token0, context.token1],
        })
        await helpers.depositFlow({
          lp: actors.lpUser0(),
          tokenId,
        })

        const { liquidity: positionLiquidity } = await context.nft.positions(tokenId)
        await erc20Helper.ensureBalancesAndApprovals(actors.lpUser0(), rewardToken, BN(50), context.staker.address)

        await Time.set(testTimestamps.startTime)
        await context.staker
          .connect(actors.lpUser0())
          .multicall([
            context.staker.interface.encodeFunctionData('createIncentive', [incentiveKey, defaultIncentiveCfg(), 50]),
            context.staker.interface.encodeFunctionData('stakeToken', [incentiveKey, tokenId]),
          ])
        ;({ remainingReward, rewardPerLiquidity, totalLiquidityStaked } = await context.staker
          .connect(actors.lpUser0())
          .incentives(incentiveId))
        expect(remainingReward).to.equal(150)
        expect(rewardPerLiquidity).to.equal(0)
        expect(totalLiquidityStaked).to.equal(positionLiquidity)
      })

      it('has gas cost', async () => {
        await snapshotGasCost(subject({}))
      })
    })

    describe('fails when', () => {
      it('is initialized with a non-contract token', async () => {
        const { startTime, endTime } = makeTimestamps(await blockTimestamp())
        await expect(
          context.staker.connect(incentiveCreator).createIncentive(
            {
              rewardToken: `0x${'badadd2e55'.repeat(4)}`,
              pool: context.pool01,
              startTime,
              endTime,
              refundee: incentiveCreator.address,
            },
            defaultIncentiveCfg(),
            totalReward,
          ),
        ).to.be.revertedWith('NonTokenContract')
      })

      describe('invalid timestamps', () => {
        it('current time is after start time', async () => {
          const params = makeTimestamps(await blockTimestamp(), 100_000)

          // Go to after the start time
          await Time.setAndMine(params.startTime + 100)

          const now = await blockTimestamp()
          expect(now).to.be.greaterThan(params.startTime, 'test setup: before start time')

          expect(now).to.be.lessThan(params.endTime, 'test setup: after end time')

          await expect(subject(params)).to.be.revertedWith('StartTimeMustBeNowOrFuture')
        })

        it('end time is before start time', async () => {
          const params = makeTimestamps(await blockTimestamp())
          params.endTime = params.startTime - 10
          await expect(subject(params)).to.be.revertedWith('StartTimeMustBeforeEndTime')
        })

        it('start time is too far into the future', async () => {
          const params = makeTimestamps((await blockTimestamp()) + 2 ** 32 + 1)
          await expect(subject(params)).to.be.revertedWith('StartTimeTooFarInFuture')
        })

        it('end time is within valid duration of start time', async () => {
          const params = makeTimestamps(await blockTimestamp())
          params.endTime = params.startTime + 2 ** 32 + 1
          await expect(subject(params)).to.be.revertedWith('IncentiveDurationTooLong')
        })
      })

      describe('invalid reward', () => {
        it('totalReward is 0 or an invalid amount', async () => {
          const now = await blockTimestamp()

          await expect(
            context.staker.connect(incentiveCreator).createIncentive(
              {
                rewardToken: context.rewardToken.address,
                pool: context.pool01,
                refundee: incentiveCreator.address,
                ...makeTimestamps(now, 1_000),
              },
              defaultIncentiveCfg(),
              BNe18(0),
            ),
          ).to.be.revertedWith('RewardMustBePositive')
        })
      })

      describe('invalid operator to update incentive', () => {
        it('invalid operator without role', async () => {
          timestamps = makeTimestamps(await blockTimestamp())

          const createIncentiveResult = await helpers.createIncentiveFlow({
            ...timestamps,
            rewardToken: context.rewardToken,
            pool: context.poolObj.address,
            refundee: incentiveCreator.address,
            totalReward,
            config: defaultIncentiveCfg(),
          })

          await expect(
            context.staker.connect(actors.lpUser0()).createIncentive(
              {
                rewardToken: createIncentiveResult.rewardToken.address,
                pool: createIncentiveResult.pool,
                refundee: createIncentiveResult.refundee,
                startTime: createIncentiveResult.startTime,
                endTime: createIncentiveResult.endTime,
              },
              defaultIncentiveCfg(),
              BNe18(0),
            ),
          ).to.be.revertedWith('AccessControlUnauthorizedAccount')
        })
      })
    })
  })

  describe('#endIncentive', () => {
    let subject: (params: Partial<ContractParams.EndIncentive>) => Promise<any>
    let createIncentiveResult: HelperTypes.CreateIncentive.Result

    beforeEach('setup', async () => {
      timestamps = makeTimestamps(await blockTimestamp())

      createIncentiveResult = await helpers.createIncentiveFlow({
        ...timestamps,
        rewardToken: context.rewardToken,
        pool: context.poolObj.address,
        totalReward,
        config: defaultIncentiveCfg(),
      })

      subject = async (params: Partial<ContractParams.EndIncentive> = {}) => {
        return await context.staker.connect(incentiveCreator).endIncentive({
          rewardToken: params.rewardToken || context.rewardToken.address,
          pool: context.pool01,
          startTime: params.startTime || timestamps.startTime,
          endTime: params.endTime || timestamps.endTime,
          refundee: incentiveCreator.address,
        })
      }
    })

    describe('works and', () => {
      it('update incentive config', async () => {
        timestamps = makeTimestamps(await blockTimestamp())

        createIncentiveResult = await helpers.createIncentiveFlow({
          ...timestamps,
          rewardToken: context.rewardToken,
          pool: context.poolObj.address,
          refundee: incentiveCreator.address,
          totalReward,
          config: defaultIncentiveCfg(),
        })

        await context.staker.connect(incentiveCreator).createIncentive(
          {
            rewardToken: createIncentiveResult.rewardToken.address,
            pool: createIncentiveResult.pool,
            refundee: createIncentiveResult.refundee,
            startTime: createIncentiveResult.startTime,
            endTime: createIncentiveResult.endTime,
          },
          { ...defaultIncentiveCfg(), minExitDuration: BN(7 * 24 * 3600), minTickWidth: 128 },
          BNe18(0),
        )

        const incentiveId = await helpers.getIncentiveId(createIncentiveResult)
        const config = await context.staker.incentiveConfigs(incentiveId)
        expect(config.minExitDuration).to.be.eq(7 * 24 * 3600)
        expect(config.minTickWidth).to.be.eq(128)
      })

      it('emits IncentiveEnded event', async () => {
        await Time.set(timestamps.endTime + 10)

        const incentiveId = await helpers.getIncentiveId(createIncentiveResult)

        await expect(subject({}))
          .to.emit(context.staker, 'IncentiveEnded')
          .withArgs(incentiveId, '100000000000000000000')
      })

      it('deletes incentives[key]', async () => {
        const incentiveId = await helpers.getIncentiveId(createIncentiveResult)
        expect((await context.staker.incentives(incentiveId)).remainingReward).to.be.gt(0)

        await Time.set(timestamps.endTime + 1)
        await subject({})
        const { remainingReward, totalLiquidityStaked } = await context.staker.incentives(incentiveId)
        expect(remainingReward).to.eq(0)
        expect(totalLiquidityStaked).to.eq(0)
      })

      it('has gas cost', async () => {
        await Time.set(timestamps.endTime + 1)
        await snapshotGasCost(subject({}))
      })
    })

    describe('reverts when', async () => {
      it('block.timestamp <= end time', async () => {
        await Time.set(timestamps.endTime - 10)
        await expect(subject({})).to.be.revertedWith('CannotEndIncentiveBeforeEndTime')
      })

      it('incentive does not exist', async () => {
        // Adjust the block.timestamp so it is after the claim deadline
        await Time.set(timestamps.endTime + 1)
        await expect(
          subject({
            startTime: (await blockTimestamp()) + 1000,
          }),
        ).to.be.revertedWith('NoRefundAvailable')
      })

      it('incentive has stakes', async () => {
        await Time.set(timestamps.startTime)
        const amountDesired = BNe18(10)
        // stake a token
        await helpers.mintDepositStakeFlow({
          lp: actors.lpUser0(),
          createIncentiveResult,
          tokensToStake: [context.token0, context.token1],
          ticks: [getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM]), getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM])],
          amountsToStake: [amountDesired, amountDesired],
        })

        // Adjust the block.timestamp so it is after the claim deadline
        await Time.set(timestamps.endTime + 1)
        await expect(subject({})).to.be.revertedWith('CannotEndIncentiveWhileStaked')
      })
    })
  })
})
