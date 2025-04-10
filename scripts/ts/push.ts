import dotenv from 'dotenv'
dotenv.config()
import { program } from '@commander-js/extra-typings'

import { Pusher__factory } from '../../typechain-types'
import { DoubleProvider, DoubleWallet, getEnv } from '../template/util'
import { getSdkEthBridge, parseIntThrowing } from './util'
import { OmitTyped } from '../../lib/arbitrum-sdk/src/lib/utils/types'
import { L1ToL2MessageGasParams } from '../../lib/arbitrum-sdk/src/lib/message/L1ToL2MessageCreator'
import {
  addCustomNetwork,
  L1ToL2MessageGasEstimator,
} from '../../lib/arbitrum-sdk/src'
import { BigNumber } from 'ethers-v5'
import {
  l1Networks,
  l2Networks,
} from '../../lib/arbitrum-sdk/src/lib/dataEntities/networks'

program
  .argument('<inbox>', 'The inbox address to push through')
  .argument('<num-blocks>', 'The number of blocks to push')
  .option(
    '--min-elapsed <blocks>',
    'The minimum number of elapsed blocks since the last push. ' +
      'If a batch was pushed more recently than this, pushing will be skipped. ' +
      'For example, if a push was performed at block 100, latest is 110. numBlocks >= 10 will skip. ' +
      'If 0, disabled.'
  )
  .option(
    '--is-custom-fee',
    'Indicates if the child chain is a custom fee child chain'
  )
  .option(
    '--manual-redeem',
    'Disable payment for auto redeem on parent chain. Always set for custom fee child chains'
  )
  .action(async (inbox, numBlocks, options) => {
    const childProvider = new DoubleProvider(getEnv('CHILD_RPC_URL'))
    const parentProvider = new DoubleProvider(getEnv('PARENT_RPC_URL'))
    const parentSigner = new DoubleWallet(
      getEnv('PARENT_PRIVATE_KEY'),
      parentProvider
    )

    const pusherAddress = getEnv('PUSHER_ADDRESS')
    const pusherContract = Pusher__factory.connect(pusherAddress, parentSigner)

    if (options.minElapsed) {
      // see if we should skip or go ahead
      const latestBlock = await parentSigner.provider.getBlockNumber()

      const logs = await parentSigner.provider.getLogs({
        address: pusherAddress,
        topics: [
          Pusher__factory.createInterface().getEvent('BlockHashesPushed')
            .topicHash,
        ],
        fromBlock: latestBlock - parseIntThrowing(options.minElapsed),
      })

      if (logs.length > 0) {
        // there was a push sufficiently recent, skip
        console.log(
          'Skipping push, recent push found at block',
          logs[0].blockNumber
        )
        return
      }
    }

    if (options.isCustomFee) {
      console.warn('Pushing with custom fee child chain, forcing manual redeem')
      options.manualRedeem = true
    }

    // default gas estimates
    let estimates: L1ToL2MessageGasParams = {
      maxSubmissionCost: BigNumber.from(0),
      maxFeePerGas: BigNumber.from(0),
      gasLimit: BigNumber.from(0),
      deposit: BigNumber.from(0),
    }
    if (!options.manualRedeem) {
      const childChainId = parseInt(
        (await childProvider.getNetwork()).chainId.toString()
      )
      const parentChainId = parseInt(
        (await parentProvider.getNetwork()).chainId.toString()
      )

      // add custom network through sdk if required
      if (!l2Networks[childChainId]) {
        addCustomNetwork({
          customL1Network:
            l1Networks[parentChainId] || l2Networks[parentChainId]
              ? undefined
              : {
                  isArbitrum: false,
                  chainID: parentChainId,
                  name: 'parentChain',
                  explorerUrl: '',
                  isCustom: true,
                  blockTime: 0,
                  partnerChainIDs: [childChainId],
                },
          customL2Network: {
            tokenBridge: {
              l1GatewayRouter: '',
              l2GatewayRouter: '',
              l1ERC20Gateway: '',
              l2ERC20Gateway: '',
              l1CustomGateway: '',
              l2CustomGateway: '',
              l1WethGateway: '',
              l2WethGateway: '',
              l2Weth: '',
              l1Weth: '',
              l1ProxyAdmin: '',
              l2ProxyAdmin: '',
              l1MultiCall: '',
              l2Multicall: '',
            },
            ethBridge: await getSdkEthBridge(inbox, parentProvider),
            partnerChainID: parentChainId,
            isArbitrum: true,
            confirmPeriodBlocks: 0,
            retryableLifetimeSeconds: 0,
            nitroGenesisBlock: 0,
            nitroGenesisL1Block: 0,
            depositTimeout: 0,
            chainID: childChainId,
            name: 'childChain',
            explorerUrl: '',
            isCustom: true,
            blockTime: 0,
            partnerChainIDs: [],
          },
        })
      }

      // estimate gas
      // we can assume non custom fee child chain because we checked for it above
      const estimationFunc = (
        depositParams: OmitTyped<L1ToL2MessageGasParams, 'deposit'>
      ) => {
        return {
          data: pusherContract.interface.encodeFunctionData('pushHash', [
            inbox,
            parseIntThrowing(numBlocks),
            depositParams.maxFeePerGas.toBigInt(),
            depositParams.gasLimit.toBigInt(),
            depositParams.maxSubmissionCost.toBigInt(),
            false,
          ]),
          to: pusherAddress,
          from: parentSigner.address,
          value: depositParams.gasLimit
            .mul(depositParams.maxFeePerGas)
            .add(depositParams.maxSubmissionCost),
        }
      }
      const gasEstimator = new L1ToL2MessageGasEstimator(childProvider.v5)
      estimates = (
        await gasEstimator.populateFunctionParams(
          estimationFunc,
          parentProvider.v5
        )
      ).estimates
    }

    // execute transaction
    const tx = await pusherContract.pushHash(
      inbox,
      parseIntThrowing(numBlocks),
      estimates.maxFeePerGas.toBigInt(),
      estimates.gasLimit.toBigInt(),
      estimates.maxSubmissionCost.toBigInt(),
      options.isCustomFee || false,
      { value: estimates.deposit.toBigInt() }
    )

    console.log('Push transaction hash:', tx.hash)
    await tx.wait()
  })
  .parse()
