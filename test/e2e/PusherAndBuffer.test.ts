import { expect } from 'chai'
import { Buffer__factory } from '../../typechain-types'
import { OrbitTestSetup, testSetup } from './testSetup'
import { ethers, Signer, Wallet } from 'ethers'
import {
  L1ToL2MessageStatus,
  L1ToL2MessageWriter,
} from '../../lib/arbitrum-sdk/src'
import { L1ContractCallTransactionReceipt } from '../../lib/arbitrum-sdk/src/lib/message/L1Transaction'
import { push } from '../../scripts/ts/lib/push'

const CREATE2_FACTORY = '0x32ea7F2A6f7a2d442bADf82fEA569BA33aD97DD6'

class FakeLogger {
  logs: string[] = []
  log(message: string) {
    this.logs.push(message)
  }
  logsContain(substr: string) {
    return this.logs.some(log => log.includes(substr))
  }
}

// function to deploy a create2 factory
async function deployCreate2Factory(fundedSigner: Signer) {
  if ((await fundedSigner.provider?.getCode(CREATE2_FACTORY)) !== '0x') {
    return
  }

  const deploymentBytecode =
    '0x604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3'
  const deployer = new Wallet(
    '0xf493488b4310b207c36723f15e2feda9dad934ea3ee10c62250c4e939e91b5c6',
    fundedSigner.provider
  )

  if ((await deployer.getNonce()) !== 0) {
    throw new Error('Deployer wallet must have nonce 0')
  }

  await (
    await fundedSigner.sendTransaction({
      to: deployer.getAddress(),
      value: ethers.parseEther('1'),
    })
  ).wait()

  const fac = await new ethers.ContractFactory(
    [],
    deploymentBytecode,
    deployer
  ).deploy()
  await fac.deploymentTransaction()!.wait()

  if ((await fac.getAddress()) !== CREATE2_FACTORY) {
    throw new Error('Deployed factory address does not match expected address')
  }
}

async function create2(salt: string, bytecode: string, signer: Signer) {
  const tx = {
    to: CREATE2_FACTORY,
    data: ethers.concat([salt, bytecode]),
  }
  const deployedAddr = ethers.getCreate2Address(
    CREATE2_FACTORY,
    salt,
    ethers.keccak256(bytecode)
  )
  await (await signer.sendTransaction(tx)).wait()
  return deployedAddr
}

describe('Pusher & Buffer', () => {
  let setup: OrbitTestSetup

  before(async function () {
    const _setup = await testSetup()
    if (!_setup.isTestingOrbit) throw new Error('Not testing Orbit')
    setup = _setup
  })

  it('should have the correct network information', async function () {
    expect(setup.l1Network.chainID).to.eq(1337)
    expect(setup.l2Network.chainID).to.eq(412346)
    expect(setup.l3Network.chainID).to.eq(333333)

    // commented out because native token isn't set correctly
    // expect(setup.l3Network.nativeToken).to.not.eq(undefined)
    // expect(setup.l3Network.nativeToken).to.not.eq(ethers.ZeroAddress)
  })

  describe('Deployment', () => {
    const create2Salt = ethers.hexlify(ethers.randomBytes(32))
    let pusherAddress: string
    let bufferAddress: string

    before(async () => {
      await deployCreate2Factory(setup.l1Signer)
      await deployCreate2Factory(setup.l2Signer)
      await deployCreate2Factory(setup.l3Signer)
    })

    it('should deploy Pusher and Buffer to L1', async function () {
      bufferAddress = await create2(
        create2Salt,
        Buffer__factory.bytecode,
        setup.l1Signer
      )
      pusherAddress = ethers.getCreateAddress({ from: bufferAddress, nonce: 1 })

      // require code at the addresses
      expect(await setup.l1Provider.getCode(bufferAddress)).to.not.eq('0x')
      expect(await setup.l1Provider.getCode(pusherAddress)).to.not.eq('0x')
    })

    it('should deploy Pusher and Buffer to L2', async function () {
      await create2(create2Salt, Buffer__factory.bytecode, setup.l2Signer)
      expect(await setup.l2Provider.getCode(bufferAddress)).to.not.eq('0x')
      expect(await setup.l2Provider.getCode(pusherAddress)).to.not.eq('0x')
    })

    it('should deploy Pusher and Buffer to L3', async function () {
      await create2(create2Salt, Buffer__factory.bytecode, setup.l3Signer)
      expect(await setup.l3Provider.getCode(bufferAddress)).to.not.eq('0x')
      expect(await setup.l3Provider.getCode(pusherAddress)).to.not.eq('0x')
    })

    async function pushTest(
      isL3: boolean,
      options: {
        isCustomFee: boolean
        manualRedeem: boolean
      }
    ) {
      const logger = new FakeLogger()
      const receipt = (await push(
        isL3 ? setup.l2Signer : setup.l1Signer,
        isL3 ? setup.l3Signer : setup.l2Signer,
        pusherAddress,
        isL3
          ? setup.l3Network.ethBridge.inbox
          : setup.l2Network.ethBridge.inbox,
        1, // todo: make this configurable
        options,
        logger.log.bind(logger)
      ))!

      // should auto redeem
      if (
        options.manualRedeem &&
        !logger.logsContain('Manual redeem complete')
      ) {
        throw new Error('manual redeem not found in logs')
      }
      if (
        !options.manualRedeem &&
        !logger.logsContain('automatically redeemed')
      ) {
        throw new Error('auto redeem not found in logs')
      }

      // check that we've pushed some block hashes
      const buffer = Buffer__factory.connect(
        bufferAddress,
        isL3 ? setup.l3Signer : setup.l2Signer
      )
      const parentChainBlockNumber = receipt.blockNumber - 1
      const blockHash = (await (
        isL3 ? setup.l2Provider : setup.l1Provider
      ).getBlock(parentChainBlockNumber))!.hash
      const pushedHash = await buffer.parentChainBlockHash(
        parentChainBlockNumber
      )
      expect(pushedHash).to.eq(blockHash, `Block hash does not match`)
    }

    describe('Pushing to L2', () => {
      it('should push 1 block to L2, and require manual redeem', async () => {
        await pushTest(false, {
          isCustomFee: false,
          manualRedeem: true,
        })
      })
      it('should push 1 block to L2, and successfully auto redeem', async () => {
        await pushTest(false, {
          isCustomFee: false,
          manualRedeem: false,
        })
      })
    })

    describe('Pushing to L3', () => {
      it('should push 1 block to L3, and require manual redeem', async () => {
        await pushTest(true, {
          isCustomFee: true,
          manualRedeem: true,
        })
      })
      it('should push 1 block to L3, and auto redeem', async () => {
        await pushTest(true, {
          isCustomFee: true,
          manualRedeem: false,
        })
      })
    })
  })
})
