import { BigNumberish } from 'ethers'
import { IUniswapV3Staker } from '../typechain-v5'

export module ContractParams {
  export type Timestamps = {
    startTime: number
    endTime: number
  }

  export type IncentiveKey = Omit<IUniswapV3Staker.IncentiveKeyStruct, keyof Timestamps> & Timestamps

  export type CreateIncentive = IncentiveKey & {
    reward: BigNumberish
  }

  export type EndIncentive = IncentiveKey
}
