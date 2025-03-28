// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ArbSys} from "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";
import {IInbox} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";

// this interface needs to be implemented by a future native solution
interface IBuffer {
    function parentBlockHash(uint256 parentBlockNumber) external view returns (bytes32);
}

contract Buffer is IBuffer {
    // these are intentionally not public
    uint256 constant bufferSize = 10; // todo: pick a reasonable size
    address immutable aliasedPusher;

    // we keep the block numbers in a ring buffer, and store the hashes in a mapping
    uint256[] blockNumberBuffer;
    uint256 bufferPtr;

    // maps block number to hash
    mapping(uint256 => bytes32) blockHashes;

    error NotPusher();
    error UnknownParentBlockHash(uint256 parentBlockNumber);

    constructor() {
        aliasedPusher = AddressAliasHelper.applyL1ToL2Alias(address(new Pusher(address(this))));
    }

    function receiveHash(uint256 blockNumber, bytes32 blockHash) external {
        if (msg.sender != aliasedPusher) revert NotPusher();

        // get the pointer position and the value at that position in the number buffer
        uint256 _bufferPtr = bufferPtr;
        uint256 valueAtPtr = blockNumberBuffer[_bufferPtr];

        // if we are overwriting a block number, delete its hash from the mapping
        if (valueAtPtr != 0) {
            blockHashes[valueAtPtr] = 0;
        }

        // write the new block number into the buffer
        blockNumberBuffer[_bufferPtr] = blockNumber;

        // write the new hash into the mapping
        blockHashes[blockNumber] = blockHash;

        // increment the pointer
        bufferPtr = (_bufferPtr + 1) % bufferSize;

        // should we emit an event? 2935 does not
    }

    function parentBlockHash(uint256 parentBlockNumber) external view returns (bytes32) {
        bytes32 _parentBlockHash = blockHashes[parentBlockNumber];

        // should this revert or simply return 0?
        if (_parentBlockHash == 0) {
            revert UnknownParentBlockHash(parentBlockNumber);
        }

        return _parentBlockHash;
    }
}

contract Pusher {
    bool immutable isL1;
    address public immutable bufferAddress;

    error NotL1OrArbitrum();

    constructor(address _bufferAddress) {
        bufferAddress = _bufferAddress;
        isL1 = block.chainid == 1;
        if (block.chainid != 1) {
            try ArbSys(address(100)).arbOSVersion() {}
            catch {
                revert NotL1OrArbitrum();
            }
        }
    }

    // we'll only push one hash for now, but we can extend later to push batches up to size 256 if we want
    /// @notice Push the hash of the previous block to the buffer on the child chain specified by inbox
    ///         For custom fee chains, the caller must either set gasPriceBid, gasLimit, and submissionCost to 0 and manually redeem on the child,
    ///         or prefund the chain's inbox with the appropriate amount of fees.
    /// @param inbox The address of the inbox on the child chain
    /// @param gasPriceBid The gas price bid for the transaction.
    /// @param gasLimit The gas limit for the transaction.
    /// @param submissionCost The cost of submitting the transaction.
    function pushHash(address inbox, uint256 gasPriceBid, uint256 gasLimit, uint256 submissionCost) external payable {
        uint256 blockNumber;
        bytes32 blockHash;
        if (isL1) {
            blockNumber = block.number - 1;
            blockHash = blockhash(blockNumber);
        } else {
            blockNumber = ArbSys(address(100)).arbBlockNumber() - 1;
            blockHash = ArbSys(address(100)).arbBlockHash(blockNumber);
        }

        IInbox(inbox).createRetryableTicket{value: msg.value}({
            to: bufferAddress,
            l2CallValue: 0,
            maxSubmissionCost: submissionCost,
            excessFeeRefundAddress: msg.sender,
            callValueRefundAddress: msg.sender,
            gasLimit: gasLimit,
            maxFeePerGas: gasPriceBid,
            data: abi.encodeCall(Buffer.receiveHash, (blockNumber, blockHash))
        });

        // todo: emit an event?
    }
}
