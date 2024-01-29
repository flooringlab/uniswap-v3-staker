import { BigNumber, BigNumberish, Wallet } from 'ethers'
import { TestERC20, IUniswapV3Staker } from '../../typechain-v5'
import { FeeAmount } from '../shared'

export module HelperTypes {
  export type CommandFunction<Input, Output> = (input: Input) => Promise<Output>

  export module CreateIncentive {
    type ReplaceBigNumberish<T> = {
      [K in keyof T]: T[K] extends BigNumberish ? BigNumber : T[K]
    }

    type CustomArgOverride = {
      rewardToken: TestERC20
      startTime: number
      endTime?: number
      refundee?: string
      pool: string
      totalReward: BigNumber
    }

    export type Args = Omit<ReplaceBigNumberish<IUniswapV3Staker.IncentiveKeyStruct>, keyof CustomArgOverride> &
      CustomArgOverride

    export type Result = Required<Args>

    export type Command = CommandFunction<Args, Result>
  }

  export module MintDepositStake {
    export type Args = {
      lp: Wallet
      tokensToStake: [TestERC20, TestERC20]
      amountsToStake: [BigNumber, BigNumber]
      ticks: [number, number]
      createIncentiveResult: CreateIncentive.Result
    }

    export type Result = {
      lp: Wallet
      tokenId: string
      stakedAt: number
    }

    export type Command = CommandFunction<Args, Result>
  }

  export module Mint {
    type Args = {
      lp: Wallet
      tokens: [TestERC20, TestERC20]
      amounts?: [BigNumber, BigNumber]
      fee?: FeeAmount
      tickLower?: number
      tickUpper?: number
    }

    export type Result = {
      lp: Wallet
      tokenId: string
    }

    export type Command = CommandFunction<Args, Result>
  }

  export module Deposit {
    type Args = {
      lp: Wallet
      tokenId: string
    }
    type Result = void
    export type Command = CommandFunction<Args, Result>
  }

  export module UnstakeCollectBurn {
    type Args = {
      lp: Wallet
      tokenId: string
      createIncentiveResult: CreateIncentive.Result
    }
    export type Result = {
      balance: BigNumber
      unstakedAt: number
    }

    export type Command = CommandFunction<Args, Result>
  }

  export module EndIncentive {
    type Args = {
      createIncentiveResult: CreateIncentive.Result
    }

    type Result = {
      amountReturnedToCreator: BigNumber
    }

    export type Command = CommandFunction<Args, Result>
  }

  export module MakeTickGo {
    type Args = {
      direction: 'up' | 'down'
      desiredValue?: number
      trader?: Wallet
    }

    type Result = { currentTick: number }

    export type Command = CommandFunction<Args, Result>
  }

  export module GetIncentiveId {
    type Args = CreateIncentive.Result

    // Returns the incentiveId as bytes32
    type Result = string

    export type Command = CommandFunction<Args, Result>
  }
}
