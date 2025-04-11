import { ethers } from 'ethers'
import { EthBridge } from '../../lib/arbitrum-sdk/src/lib/dataEntities/networks'
import { DoubleProvider } from '../template/util'

export function parseIntThrowing(x: string): number {
  const parsed = parseInt(x, 10)
  if (isNaN(parsed)) {
    throw new Error(`Cannot parse ${x} as a number`)
  }
  return parsed
}

export async function getSdkEthBridge(
  inbox: string,
  provider: DoubleProvider
): Promise<EthBridge> {
  const inboxContract = new ethers.Contract(
    inbox,
    [
      'function bridge() external view returns (address)',
      'function sequencerInbox() external view returns (address)',
    ],
    provider
  )
  const bridge = await inboxContract.bridge()
  const bridgeContract = new ethers.Contract(
    bridge,
    ['function rollup() external view returns (address)'],
    provider
  )
  const sequencerInbox = await inboxContract.sequencerInbox()
  const rollup = await bridgeContract.rollup()
  const rollupContract = new ethers.Contract(
    rollup,
    ['function outbox() external view returns (address)'],
    provider
  )
  const outbox = await rollupContract.outbox()
  return {
    inbox,
    bridge,
    sequencerInbox,
    outbox,
    rollup,
  }
}
