# Block Hash Pusher

These contracts make parent chain block hashes available to Arbitrum chains. 

There are two contracts: the `Pusher` and `Buffer`. The `Pusher` exists on each parent chain, allowing callers to send block hashes up to a `Buffer` contract on any child chain.

Both contracts are deployed via the CREATE2 factory at `0x4e59b44847b379578588920cA78FbF26c0B4956C` using the salt `0xeb44f642e5f5e0fa3d1a50c1ffbb26f929a86ade59a78f8ef4968dc9b88d15a0`, resulting in the following contract addresses on all chains:

* `Buffer`: `0x0000000048C4Ed10cF14A02B9E0AbDDA5227b071`
* `Pusher`: `0x5a5C4f3D0F0Efaeed2aEc9B59B67eC62a4666D88`