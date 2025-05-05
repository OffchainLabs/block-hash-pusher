import { BigNumber } from 'ethers-v5'
import { L1ToL2MessageGasParams } from '../../../lib/arbitrum-sdk/src/lib/message/L1ToL2MessageCreator'
import {
  IERC20__factory,
  IERC20Bridge__factory,
  IPusher__factory,
} from '../../../typechain-types'
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
import { L1ToL2MessageWriter } from '../../../lib/arbitrum-sdk/src/lib/message/L1ToL2Message'
import { ethers } from 'ethers'

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
  const pusherContract = IPusher__factory.connect(pusherAddress, parentSigner)

  // see if we should skip or go ahead
  if (options.minElapsed) {
    const latestBlock = await parentSigner.provider.getBlockNumber()

    const logs = await parentSigner.provider.getLogs({
      address: pusherAddress,
      topics: [
        IPusher__factory.createInterface().getEvent('BlockHashesPushed')
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

  const childChainId = parseInt(
    (await childSigner.provider.getNetwork()).chainId.toString()
  )
  const parentChainId = parseInt(
    (await parentSigner.provider.getNetwork()).chainId.toString()
  )

  // add custom network through sdk if required
  const ethBridge = await getSdkEthBridge(inbox, parentSigner.doubleProvider)
  const nativeToken = options.isCustomFee
    ? await IERC20Bridge__factory.connect(
        ethBridge.bridge,
        parentSigner
      ).nativeToken()
    : undefined
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
        ethBridge,
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
        nativeToken,
      },
    })
  }

  // default gas estimates
  let estimates: L1ToL2MessageGasParams

  // if custom fee and manual redeem, use zeros
  // if custom fee and auto redeem, estimate all
  // if eth and manual, estimate submission
  // if eth and auto, estimate all
  const gasEstimator = new L1ToL2MessageGasEstimator(childSigner.v5.provider)
  if (options.isCustomFee && options.manualRedeem) {
    estimates = {
      maxSubmissionCost: BigNumber.from(0),
      maxFeePerGas: BigNumber.from(0),
      gasLimit: BigNumber.from(0),
      deposit: BigNumber.from(0),
    }
  } else {
    if (options.isCustomFee) {
      // we need to approve the pusher contract prior to estimation
      const token = IERC20__factory.connect(nativeToken!, parentSigner)
      const currAllowance = await token.allowance(
        parentSigner.address,
        pusherAddress
      )
      if (currAllowance !== ethers.MaxUint256) {
        const approveTx = await token.approve(pusherAddress, ethers.MaxUint256)
        log(`Approving Pusher contract ${approveTx.hash}`)
        await approveTx.wait()
        log(`Pusher contract approved`)
      }
    }

    // estimate gas
    const estimationFunc = (
      depositParams: OmitTyped<L1ToL2MessageGasParams, 'deposit'>
    ) => {
      return {
        data: pusherContract.interface.encodeFunctionData('pushHashes', [
          inbox,
          numBlocks,
          depositParams.maxFeePerGas.toBigInt(),
          depositParams.gasLimit.toBigInt(),
          depositParams.maxSubmissionCost.toBigInt(),
          options.isCustomFee || false,
        ]),
        to: pusherAddress,
        from: parentSigner.address,
        value: options.isCustomFee
          ? 0
          : depositParams.gasLimit
              .mul(depositParams.maxFeePerGas)
              .add(depositParams.maxSubmissionCost),
      }
    }

    estimates = (
      await gasEstimator.populateFunctionParams(
        estimationFunc,
        parentSigner.doubleProvider.v5
      )
    ).estimates

    // if we are manually redeeming, we only provide the max submission cost
    if (options.manualRedeem) {
      estimates.gasLimit = BigNumber.from(0)
      estimates.maxFeePerGas = BigNumber.from(0)
      estimates.deposit = estimates.maxSubmissionCost
    }
  }

  // execute transaction
  const tx = await pusherContract.pushHashes(
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
  } else if (waitResult.status === L1ToL2MessageStatus.FUNDS_DEPOSITED_ON_L2) {
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
  } else {
    throw new Error(`Unexpected Message Status: ${waitResult.status}`)
  }

  return receipt
}
