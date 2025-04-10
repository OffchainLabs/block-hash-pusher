import { BigNumber } from 'ethers-v5'
import { L1ToL2MessageGasParams } from '../../../lib/arbitrum-sdk/src/lib/message/L1ToL2MessageCreator'
import { Pusher__factory } from '../../../typechain-types'
import { DoubleProvider, DoubleWallet } from '../../template/util'
import { getSdkEthBridge } from '../util'
import {
  addCustomNetwork,
  l1Networks,
  l2Networks,
} from '../../../lib/arbitrum-sdk/src/lib/dataEntities/networks'
import { OmitTyped } from '../../../lib/arbitrum-sdk/src/lib/utils/types'
import { L1ToL2MessageGasEstimator } from '../../../lib/arbitrum-sdk/src'

export async function pushCommand(
  parentSigner: DoubleWallet,
  childProvider: DoubleProvider,
  pusherAddress: string,
  inbox: string,
  numBlocks: number,
  options: {
    minElapsed?: number
    isCustomFee?: boolean
    manualRedeem?: boolean
  },
  log: (message: string) => void
) {
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
      fromBlock: latestBlock - options.minElapsed,
    })

    if (logs.length > 0) {
      // there was a push sufficiently recent, skip
      log(`Skipping push, recent push found at block ${logs[0].blockNumber}`)
      return
    }
  }

  if (options.isCustomFee) {
    log('Pushing with custom fee child chain, forcing manual redeem')
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
      (await parentSigner.provider.getNetwork()).chainId.toString()
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
          ethBridge: await getSdkEthBridge(inbox, parentSigner.doubleProvider),
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
          numBlocks,
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
        parentSigner.doubleProvider.v5
      )
    ).estimates
  }

  // execute transaction
  const tx = await pusherContract.pushHash(
    inbox,
    numBlocks,
    estimates.maxFeePerGas.toBigInt(),
    estimates.gasLimit.toBigInt(),
    estimates.maxSubmissionCost.toBigInt(),
    options.isCustomFee || false,
    { value: estimates.deposit.toBigInt() }
  )
  log(
    `Pushed ${numBlocks} blocks through inbox ${inbox} with tx ${tx.hash}, waiting for confirmation...`
  )
  const receipt = await tx.wait()
  log(`Push confirmed in block ${receipt!.blockNumber}`)
  return receipt!
}
