import { BigNumber } from 'ethers'
import { ethers } from 'hardhat'
import { TestRewardMath } from '../../../typechain-v5'
import { days, expect } from '../../shared'

describe('unit/RewardMath', () => {
  let rewardMath: TestRewardMath

  before('setup test reward math', async () => {
    const factory = await ethers.getContractFactory('TestRewardMath')
    rewardMath = (await factory.deploy()) as TestRewardMath
  })

  it('distribute over 20% of the total duration', async () => {
    const rewardPerShareDiff = await rewardMath.computeRewardPerShareDiff(1000, 100, 200, 100, 120)
    // 1000 * 0.2 / 100
    expect(rewardPerShareDiff).to.eq(BigNumber.from(2))
  })

  it('all the liquidity for the duration and none of the liquidity after the end time for a whole duration', async () => {
    const rewardPerShareDiff = await rewardMath.computeRewardPerShareDiff(1000, 100, 200, 100, 200)
    // 1000 / 100
    expect(rewardPerShareDiff).to.eq(BigNumber.from(10))
  })

  it('all the liquidity for the duration and none of the liquidity after the end time for one second', async () => {
    const rewardPerShareDiff = await rewardMath.computeRewardPerShareDiff(1000, 100, 200, 100, 201)
    // 1000 / 100
    expect(rewardPerShareDiff).to.eq(BigNumber.from(10))
  })

  it('0 rewards left gets 0 reward', async () => {
    const rewardPerShareDiff = await rewardMath.computeRewardPerShareDiff(0, 100, 200, 100, 201)
    expect(rewardPerShareDiff).to.eq(BigNumber.from(0))
  })

  it('0 difference in seconds gets 0 reward', async () => {
    const rewardPerShareDiff = await rewardMath.computeRewardPerShareDiff(1000, 100, 200, 100, 100)
    expect(rewardPerShareDiff).to.eq(BigNumber.from(0))
  })

  it('0 liquidity share gets 0 reward', async () => {
    const rewardPerShareDiff = await rewardMath.computeRewardPerShareDiff(1000, 0, 200, 100, 200)
    expect(rewardPerShareDiff).to.eq(BigNumber.from(0))
  })

  it('0 reward after expired', async () => {
    const rewardPerShareDiff = await rewardMath.computeRewardPerShareDiff(1000, 100, 200, 200, 300)
    expect(rewardPerShareDiff).to.eq(BigNumber.from(0))
  })

  it('reward with shares diff', async () => {
    const reward = await rewardMath.computeRewardAmount(100, 1, 3)
    expect(reward).to.eq(BigNumber.from(200))
  })

  it('0 diff gets 0 reward', async () => {
    const reward = await rewardMath.computeRewardAmount(100, 3, 3)
    expect(reward).to.eq(BigNumber.from(0))
  })

  it('0 share gets 0 reward', async () => {
    const reward = await rewardMath.computeRewardAmount(0, 3, 15)
    expect(reward).to.eq(BigNumber.from(0))
  })

  it('all rewards to penalty as staking duration is 0', async () => {
    const { ownerEarning, liquidatorEarning, refunded } = await rewardMath.computeRewardDistribution(
      1000,
      100,
      100,
      /*penaltyDecayPeriod*/ days(1),
      100,
      2000,
    )
    expect(ownerEarning).to.eq(BigNumber.from(0))
    expect(liquidatorEarning).to.eq(BigNumber.from(200))
    expect(refunded).to.eq(BigNumber.from(8000))
  })

  it('linear decay within one half life period', async () => {
    const { ownerEarning, liquidatorEarning, refunded } = await rewardMath.computeRewardDistribution(
      1000,
      /*stakedSince*/ days(1),
      /*currentTime*/ days(1.5),
      /*penaltyDecayPeriod*/ days(1),
      100,
      2000,
    )
    // 1000 - 750
    expect(ownerEarning).to.eq(BigNumber.from(0))
    expect(liquidatorEarning).to.eq(BigNumber.from(150))
    expect(refunded).to.eq(BigNumber.from(600))
  })
})
