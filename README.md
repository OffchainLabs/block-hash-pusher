# Block Hash Pusher
qwoeifjqoiwefjoiqwefj
To temporarily work around parent chain block hashes being unavailable natively on Arbitrum chains, we have an application layer solution here.

There are two contracts: `Pusher` and `ParentBlockHashBuffer`. The `Pusher` takes an `IInbox` parameter and pushes block hashes through to the `ParentBlockHashBuffer` on the child chain. 

The buffer contract will have the same address on all chains. This will allow us to eventually perform an ArbOS upgrade to start pushing hashes in there similarly to EIP2935.
