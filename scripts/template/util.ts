import { JsonRpcProvider, Provider, Wallet } from 'ethers'
import { ethers as ethersv5 } from 'ethers-v5'

export type Unwrap<T> = T extends Promise<infer U> ? U : T

export function getEnv(name: string): string {
  const value = process.env[name] || ''
  if (value === '') {
    throw new Error(`Environment variable ${name} is not defined`)
  }
  return value
}

export class DoubleProvider extends JsonRpcProvider {
  public readonly v5: ethersv5.providers.JsonRpcProvider
  constructor(public readonly url: string) {
    super(url)
    this.v5 = new ethersv5.providers.JsonRpcProvider(url)
    this.v5.on('debug', (info) => {
      if (info.action === 'request') {
        console.log('REQUEST:')
        console.log(info.request)
      }
      else if (info.action === 'response') {
        console.log('RESPONSE:')
        console.log(
          info.response
        )
        if (info.error) {
          console.log('ERROR:')
          console.log({
            code: info.error.code,
            message: info.error.message,
            data: info.error.data
          })
        }
      }
    })
  }
}

export class DoubleWallet extends Wallet {
  public readonly provider!: Provider
  public readonly v5: ethersv5.Wallet & {
    provider: ethersv5.providers.JsonRpcProvider
  }

  constructor(
    privateKey: string,
    public readonly doubleProvider: DoubleProvider
  ) {
    super(privateKey, doubleProvider)
    this.v5 = new ethersv5.Wallet(
      privateKey,
      doubleProvider.v5
    ) as ethersv5.Wallet & { provider: ethersv5.providers.JsonRpcProvider }
  }
}
