// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IBuffer} from "./interfaces/IBuffer.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";
import {Pusher} from "./Pusher.sol";

/// @notice An implementation of the IBuffer interface.
/// @dev    This contract is deployed with CREATE2 on all chains to the same address.
///         This contract's bytecode may or may not be overwritten in a future ArbOS upgrade.
contract Buffer is IBuffer {
    struct BufferItem {
        bool pushedBySystem;
        uint248 blockNumber;
    }

    /// @dev The size of the ring buffer. This is the maximum number of block hashes that can be stored.
    ///      Assuming a parent block time of 250ms and L1 block time of 12s,
    ///      then the amount of time that the buffer covers is equivalent to EIP-2935's.
    uint256 constant bufferSize = 393168;

    /// @dev A system address that is authorized to push hashes to the buffer.
    address constant systemPusher = address(0xA4B05); // todo: choose a good address for this

    /// @dev The aliased address of the pusher contract on the parent chain.
    address immutable aliasedPusher;

    /// @dev A pointer into the ring buffer. This is the index of the next block number to be pushed.
    uint256 bufferPtr;

    /// @dev Maps block numbers to their hashes. This is a mapping of block number to block hash.
    ///      Block hashes are deleted from the mapping when they are overwritten in the ring buffer.
    mapping(uint256 => bytes32) blockHashMapping;

    /// @dev A gap in the storage layout to allow for future storage variables.
    ///      It's unlikely this will be needed.
    uint256[50] __gap;

    /// @dev A ring buffer of block numbers whose hashes are stored in the `blockHashes` mapping.
    ///      Should be the last storage variable declared to maintain flexibility in resizing the buffer.
    BufferItem[bufferSize] blockNumberBuffer;

    /// @notice Thrown by `parentBlockHash` when the block hash for a given block number is not found.
    error UnknownParentBlockHash(uint256 parentBlockNumber);
    /// @dev Thrown when the caller is not authorized to push hashes.
    error NotPusher();
    /// @dev Thrown when a given range cannot be pushed to the buffer.
    error InvalidBlockRange(uint256 last, uint256 startOfRange, uint256 lengthOfRange);

    constructor() {
        aliasedPusher = AddressAliasHelper.applyL1ToL2Alias(address(new Pusher(address(this))));
    }

    /// @inheritdoc IBuffer
    function parentBlockHash(uint256 parentBlockNumber) external view returns (bytes32) {
        bytes32 _parentBlockHash = blockHashMapping[parentBlockNumber];

        // QUESTION: should this revert or simply return 0?
        if (_parentBlockHash == 0) {
            revert UnknownParentBlockHash(parentBlockNumber);
        }

        return _parentBlockHash;
    }

    /// @dev Pushes some block hashes to the ring buffer. Can only be called by the aliased pusher contract or chain owners.
    ///      The last block in the buffer must be less than the last block being pushed.
    /// @param firstBlockNumber The block number of the first block in the batch.
    /// @param blockHashes The hashes of the blocks to be pushed. These are assumed to be in contiguous order.
    function receiveHashes(uint256 firstBlockNumber, bytes32[] calldata blockHashes) external {
        uint256 startPtr = bufferPtr;
        uint256 prevPtr = (startPtr + bufferSize - 1) % bufferSize;
        BufferItem memory prevBufferItem = blockNumberBuffer[prevPtr];
        uint256 prevBlockNumber = prevBufferItem.blockNumber;

        // once the system pusher has pushed a block, only the system pusher can push more blocks
        if (
            (prevBufferItem.pushedBySystem && msg.sender != systemPusher)
                || (msg.sender != systemPusher && msg.sender != aliasedPusher)
        ) {
            revert NotPusher();
        }

        // if the previous value in the ring buffer is >= firstBlockNumber, adjust the range we are writing to start from prev + 1
        // determine the range of block numbers we are writing [writeStart, writeEnd)
        uint256 writeStart = prevBlockNumber >= firstBlockNumber ? prevBlockNumber + 1 : firstBlockNumber;
        uint256 writeEnd = firstBlockNumber + blockHashes.length;

        // ensure the range is valid
        if (writeEnd <= writeStart) {
            revert InvalidBlockRange(prevBlockNumber, firstBlockNumber, blockHashes.length);
        }

        // write to the buffer in a loop
        // todo: there's a potential optimization where we don't write to the buffer every block and instead write a range.
        // i think it is probably not worth the complexity, at least in arb1's case.
        // rationale being that we'll get a new batch of hashes after every sequencer batch, which happens every few minutes.
        // on orbit chains with lower batch posting frequency, this optimization may be worth it if ArbOS is backfilling.
        // on the other hand though, the pushing transaction will not actually consume gas
        for (uint256 blockToWrite = writeStart; blockToWrite < writeEnd; blockToWrite++) {
            uint256 currPtr = (startPtr + blockToWrite - writeStart) % bufferSize;

            // if we are overwriting a block number, delete its hash from the mapping
            uint256 valueAtPtr = blockNumberBuffer[currPtr].blockNumber;
            if (valueAtPtr != 0) {
                blockHashMapping[valueAtPtr] = 0;
            }

            // write the new block number into the buffer
            blockNumberBuffer[currPtr] =
                BufferItem({pushedBySystem: msg.sender == systemPusher, blockNumber: uint248(blockToWrite)});

            // write the new hash into the mapping
            blockHashMapping[blockToWrite] = blockHashes[blockToWrite - firstBlockNumber];
        }

        // increment the pointer
        bufferPtr = (startPtr + writeEnd - writeStart) % bufferSize;
    }
}
