import dotenv from 'dotenv'
dotenv.config()
import { program } from '@commander-js/extra-typings'
import { push } from './lib/push'
import { DoubleProvider, DoubleWallet, getEnv } from '../template/util'
import { parseIntThrowing } from './util'

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
    push(
      new DoubleWallet(
        getEnv('PARENT_PRIVATE_KEY'),
        new DoubleProvider(getEnv('PARENT_RPC_URL'))
      ),
      new DoubleWallet(
        getEnv('CHILD_PRIVATE_KEY'),
        new DoubleProvider(getEnv('CHILD_RPC_URL'))
      ),
      getEnv('PUSHER_ADDRESS'),
      inbox,
      parseIntThrowing(numBlocks),
      {
        ...options,
        minElapsed: options.minElapsed
          ? parseIntThrowing(options.minElapsed)
          : undefined,
      },
      console.log
    )
  })
  .parse()
