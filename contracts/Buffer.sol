// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IBuffer} from "./interfaces/IBuffer.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";
import {Pusher} from "./Pusher.sol";

/// @notice An implementation of the IBuffer interface.
/// @dev    This contract is deployed with CREATE2 on all chains to the same address.
///         This contract's bytecode may or may not be overwritten in a future ArbOS upgrade.
contract Buffer is IBuffer {
    /// @inheritdoc IBuffer
    uint256 public constant bufferSize = 393168;

    /// @inheritdoc IBuffer
    address public constant systemPusher = address(0xA4B05);

    /// @inheritdoc IBuffer
    address public immutable aliasedPusher;

    /// @dev A gap in the storage layout to allow for future storage variables.
    ///      It's unlikely this will be needed.
    uint256[50] __gap;

    /// @inheritdoc IBuffer
    bool public systemHasPushed;

    /// @inheritdoc IBuffer
    uint64 public newestBlockNumber;

    /// @inheritdoc IBuffer
    mapping(uint256 => bytes32) public blockHashMapping;

    /// @inheritdoc IBuffer
    uint256[bufferSize] public blockNumberBuffer;

    constructor() {
        aliasedPusher = AddressAliasHelper.applyL1ToL2Alias(address(new Pusher(address(this))));
    }

    /// @inheritdoc IBuffer
    function parentChainBlockHash(uint256 parentChainBlockNumber) external view returns (bytes32) {
        bytes32 _parentChainBlockHash = blockHashMapping[parentChainBlockNumber];

        if (_parentChainBlockHash == 0) {
            revert UnknownParentChainBlockHash(parentChainBlockNumber);
        }

        return _parentChainBlockHash;
    }

    /// @inheritdoc IBuffer
    function receiveHashes(uint256 firstBlockNumber, bytes32[] calldata blockHashes) external {
        // access control
        if (systemHasPushed) {
            // if the system has pushed, only the system can push
            if (msg.sender != systemPusher) {
                revert NotPusher();
            }
        } else if (msg.sender == systemPusher) {
            // if the system has not previously pushed, and is pushing now, set the flag
            systemHasPushed = true;
        } else if (msg.sender != aliasedPusher) {
            // the caller is neither the system pusher nor the aliased pusher
            revert NotPusher();
        }

        // write the hashes to the buffer, evicting old hashes as necessary
        for (uint256 i = 0; i < blockHashes.length; i++) {
            uint256 blockNumber = firstBlockNumber + i;
            uint256 bufferIndex = blockNumber % bufferSize;
            uint256 existingBlockNumber = blockNumberBuffer[bufferIndex];
            if (blockNumber <= existingBlockNumber) {
                // noop
                continue;
            }
            if (existingBlockNumber != 0) {
                // evict the old block hash
                blockHashMapping[existingBlockNumber] = 0;
            }
            // store the new block hash
            blockHashMapping[blockNumber] = blockHashes[i];
            blockNumberBuffer[bufferIndex] = blockNumber;
        }

        uint256 lastBlockNumber = firstBlockNumber + blockHashes.length - 1;

        if (lastBlockNumber > newestBlockNumber) {
            // update the newest block number
            newestBlockNumber = uint64(lastBlockNumber);
        }

        emit BlockHashesPushed(firstBlockNumber, lastBlockNumber);
    }
}
