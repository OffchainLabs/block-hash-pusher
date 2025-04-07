// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ArbSys} from "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";
import {ArbitrumChecker} from "@arbitrum/nitro-contracts/src/libraries/ArbitrumChecker.sol";
import {IInbox} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";

/// @notice This contract is a ring buffer that stores parent chain block hashes.
/// @dev    This is the guaranteed, public interface for the buffer contract. Future versions may add more functions.
///         Other functions of a given implementation not included in this interface are not guaranteed to be stable.
///         The ring buffer is sparse, meaning the block numbers are not guaranteed to be contiguous.
///         A future version may or may not change the implementation of the ring buffer to be dense.
///         The size of the ring buffer may increase or decrease in future versions.
interface IBuffer {
    function parentBlockHash(uint256 parentBlockNumber) external view returns (bytes32);
}

/// @notice An implementation of the IBuffer interface.
/// @dev    This contract is deployed with CREATE2 on all chains to the same address.
///         This contract's bytecode may or may not be overwritten in a future ArbOS upgrade.
contract Buffer is IBuffer {
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

    /// @dev A gap in the storage layout to allow for future storage variables
    uint256[50] __gap;

    /// @dev A ring buffer of block numbers whose hashes are stored in the `blockHashes` mapping.
    ///      Should be the last storage variable declared to maintain flexibility in resizing the buffer.
    uint256[bufferSize] blockNumberBuffer;

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

    /// @dev Pushes a block hash to the ring buffer. Can only be called by the aliased pusher contract or chain owners.
    /// @param firstBlockNumber The block number of the first block in the batch.
    /// @param blockHashes The hashes of the blocks to be pushed. These are assumed to be in contiguous order.
    function receiveHashes(uint256 firstBlockNumber, bytes32[] calldata blockHashes) external {
        if (msg.sender != systemPusher && msg.sender != aliasedPusher) revert NotPusher();

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
        // todo: there's a potential optimization where we don't write to the buffer every block and instead write a range
        for (uint256 blockToWrite = writeStart; blockToWrite < writeEnd; blockToWrite++) {
            uint256 currPtr = (startPtr + blockToWrite - writeStart) % bufferSize;

            // if we are overwriting a block number, delete its hash from the mapping
            uint256 valueAtPtr = blockNumberBuffer[currPtr];
            if (valueAtPtr != 0) {
                blockHashMapping[valueAtPtr] = 0;
            }

            // write the new block number into the buffer
            blockNumberBuffer[currPtr] = blockToWrite;
            // write the new hash into the mapping
            blockHashMapping[blockToWrite] = blockHashes[blockToWrite - firstBlockNumber];
        }

        // increment the pointer
        bufferPtr = (startPtr + writeEnd - writeStart) % bufferSize;
    }
}

/// @notice The Pusher gets the hash of the previous block and pushes it to the buffer on the child chain via retryable ticket.
contract Pusher {
    /// @notice Whether this contract is deployed on an Arbitrum chain.
    ///         This condition changes the way the block number is retrieved.
    bool public immutable isArbitrum;
    /// @notice The address of the buffer contract on the child chain.
    address public immutable bufferAddress;

    /// @notice Thrown when the amount of ETH sent to the contract is not equal to the specified retryable ticket cost.
    error WrongEthAmount(uint256 received, uint256 expected);

    constructor(address _bufferAddress) {
        bufferAddress = _bufferAddress;
        isArbitrum = ArbitrumChecker.runningOnArbitrum();
    }

    // we'll only push one hash for now, but we can extend later to push batches up to size 256 if we want
    /// @notice Push the hash of the previous block to the buffer on the child chain specified by inbox
    ///         For custom fee chains, the caller must either set gasPriceBid, gasLimit, and submissionCost to 0 and manually redeem on the child,
    ///         or prefund the chain's inbox with the appropriate amount of fees.
    ///         (this is an [efficiency + implementation simplicity] vs [operator UX] tradeoff)
    /// @param inbox The address of the inbox on the child chain
    /// @param gasPriceBid The gas price bid for the transaction.
    /// @param gasLimit The gas limit for the transaction.
    /// @param submissionCost The cost of submitting the transaction.
    function pushHash(address inbox, uint256 gasPriceBid, uint256 gasLimit, uint256 submissionCost) external payable {
        uint256 blockNumber;
        bytes32 blockHash;
        if (isArbitrum) {
            blockNumber = ArbSys(address(100)).arbBlockNumber() - 1;
            blockHash = ArbSys(address(100)).arbBlockHash(blockNumber);
        } else {
            blockNumber = block.number - 1;
            blockHash = blockhash(blockNumber);
        }

        if (gasPriceBid * gasLimit + submissionCost != msg.value) {
            revert WrongEthAmount(msg.value, gasPriceBid * gasLimit + submissionCost);
        }

        bytes32[] memory blockHashes = new bytes32[](1);
        blockHashes[0] = blockHash;
        IInbox(inbox).createRetryableTicket{value: msg.value}({
            to: bufferAddress,
            l2CallValue: 0,
            maxSubmissionCost: submissionCost,
            excessFeeRefundAddress: msg.sender,
            callValueRefundAddress: msg.sender,
            gasLimit: gasLimit,
            maxFeePerGas: gasPriceBid,
            data: abi.encodeCall(Buffer.receiveHashes, (blockNumber, blockHashes))
        });

        // QUESTION: emit an event?
    }
}
