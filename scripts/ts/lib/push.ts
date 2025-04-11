import { BigNumber } from 'ethers-v5'
import { L1ToL2MessageGasParams } from '../../../lib/arbitrum-sdk/src/lib/message/L1ToL2MessageCreator'
import { Pusher__factory } from '../../../typechain-types'
import { DoubleWallet } from '../../template/util'
import { getSdkEthBridge } from '../util'
import {
  addCustomNetwork,
  l1Networks,
  l2Networks,
} from '../../../lib/arbitrum-sdk/src/lib/dataEntities/networks'
import { OmitTyped } from '../../../lib/arbitrum-sdk/src/lib/utils/types'
import {
  L1ToL2MessageGasEstimator,
  L1ToL2MessageStatus,
} from '../../../lib/arbitrum-sdk/src'
import { L1ContractCallTransactionReceipt } from '../../../lib/arbitrum-sdk/src/lib/message/L1Transaction'
import {
  L1ToL2MessageWriter,
} from '../../../lib/arbitrum-sdk/src/lib/message/L1ToL2Message'

export async function push(
  parentSigner: DoubleWallet,
  childSigner: DoubleWallet,
  pusherAddress: string,
  inbox: string,
  numBlocks: number,
  options: {
    minElapsed?: number
    isCustomFee?: boolean
    manualRedeem?: boolean
  },
  log: (message: string) => void // custom log function so tests can check logs and reduce noise
): Promise<L1ContractCallTransactionReceipt | undefined> {
  const pusherContract = Pusher__factory.connect(pusherAddress, parentSigner)

  // see if we should skip or go ahead
  if (options.minElapsed) {
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

  const childChainId = parseInt(
    (await childSigner.provider.getNetwork()).chainId.toString()
  )
  const parentChainId = parseInt(
    (await parentSigner.provider.getNetwork()).chainId.toString()
  )

  // add custom network through sdk if required
  if (!l2Networks[childChainId]) {
    console.log('adding custom l2 network')
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
        depositTimeout: 1800000,
        chainID: childChainId,
        name: 'childChain',
        explorerUrl: '',
        isCustom: true,
        blockTime: 0,
        partnerChainIDs: [],
      },
    })
  }

  // default gas estimates
  let estimates: L1ToL2MessageGasParams = {
    maxSubmissionCost: BigNumber.from(0),
    maxFeePerGas: BigNumber.from(0),
    gasLimit: BigNumber.from(0),
    deposit: BigNumber.from(0),
  }
  if (!options.manualRedeem) {
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
    const gasEstimator = new L1ToL2MessageGasEstimator(childSigner.v5.provider)
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

  log(`Parent transaction sent, waiting for confirmation. Hash: ${tx.hash}`)

  const receipt = new L1ContractCallTransactionReceipt(
    await parentSigner.v5.provider.getTransactionReceipt(
      (await tx.wait())!.hash
    )
  )

  log(`Parent transaction confirmed ${receipt!.blockNumber}`)

  // wait for redemption on child chain
  const waitResult = await receipt.waitForL2(childSigner.v5)
  if (waitResult.status === L1ToL2MessageStatus.REDEEMED) {
    log('Message automatically redeemed')
  }
  else if (waitResult.status === L1ToL2MessageStatus.FUNDS_DEPOSITED_ON_L2) {
    log('Attempting manual redeem')
    const message = (await receipt.getL1ToL2Messages(childSigner.v5))[0]
    const writer = new L1ToL2MessageWriter(
      childSigner.v5,
      message.chainId,
      message.sender,
      message.messageNumber,
      message.l1BaseFee,
      message.messageData
    )
    const redemption = await writer.redeem()
    await redemption.wait()
    log('Manual redeem complete')
  }
  else {
    throw new Error(
      `Unexpected Message Status: ${waitResult.status}`
    )
  }

  return receipt
}
