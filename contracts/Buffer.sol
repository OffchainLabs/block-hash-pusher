// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IBuffer} from "./interfaces/IBuffer.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";
import {Pusher} from "./Pusher.sol";

/// @notice An implementation of the IBuffer interface.
/// @dev    This contract is deployed with CREATE2 on all chains to the same address.
///         This contract's bytecode may or may not be overwritten in a future ArbOS upgrade.
contract Buffer is IBuffer {
    /// @dev The size of the ring buffer. This is the maximum number of block hashes that can be stored.
    ///      Assuming a parent block time of 250ms and L1 block time of 12s,
    ///      then the amount of time that the buffer covers is equivalent to EIP-2935's.
    uint256 public constant bufferSize = 393168;

    /// @dev A system address that is authorized to push hashes to the buffer.
    address public constant systemPusher = address(0xA4B05); // todo: choose a good address for this

    /// @dev The aliased address of the pusher contract on the parent chain.
    address public immutable aliasedPusher;

    /// @dev A gap in the storage layout to allow for future storage variables.
    ///      It's unlikely this will be needed.
    uint256[50] __gap;

    /// @notice Whether the system address has pushed a block hash to the buffer.
    ///         Once this is set, only the system address can push more hashes.
    bool public systemHasPushed;

    /// @dev A pointer into the ring buffer. This is the index of the next block number to be pushed.
    uint248 public bufferPtr;

    /// @dev Maps block numbers to their hashes. This is a mapping of block number to block hash.
    ///      Block hashes are deleted from the mapping when they are overwritten in the ring buffer.
    mapping(uint256 => bytes32) public blockHashMapping;

    /// @dev A ring buffer of block numbers whose hashes are stored in the `blockHashes` mapping.
    ///      Should be the last storage variable declared to maintain flexibility in resizing the buffer.
    uint256[bufferSize] public blockNumberBuffer;

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

    /// @inheritdoc IBuffer
    function receiveHashes(uint256 firstBlockNumber, bytes32[] calldata blockHashes) external {
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

        uint256 startPtr = bufferPtr;
        uint256 prevPtr = (startPtr + bufferSize - 1) % bufferSize;
        uint256 prevBlockNumber = blockNumberBuffer[prevPtr];

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
            uint256 valueAtPtr = blockNumberBuffer[currPtr];
            if (valueAtPtr != 0) {
                blockHashMapping[valueAtPtr] = 0;
            }

            // write the new block number into the buffer
            blockNumberBuffer[currPtr] =blockToWrite;

            // write the new hash into the mapping
            blockHashMapping[blockToWrite] = blockHashes[blockToWrite - firstBlockNumber];
        }

        // increment the pointer
        bufferPtr = uint248((startPtr + writeEnd - writeStart) % bufferSize);
    }
}
