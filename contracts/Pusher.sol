// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ArbSys} from "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";
import {ArbOwnerPublic} from "@arbitrum/nitro-contracts/src/ownership/ArbOwnerPublic.sol";
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
    /// @notice The size of the ring buffer. This is the maximum number of block hashes that can be stored.
    /// @dev    Assuming a parent block time of 250ms and L1 block time of 12s,
    ///         then the amount of time that the buffer covers is equivalent to EIP-2935's.
    uint256 public constant bufferSize = 393168;

    /// @notice The aliased address of the pusher contract on the parent chain.
    ///         This address + chain owners are authorized to push hashes.
    address public immutable aliasedPusher;

    // we keep the block numbers in a ring buffer, and store the hashes in a mapping
    uint256[] public blockNumberBuffer;
    uint256 public bufferPtr;

    // maps block number to hash
    mapping(uint256 => bytes32) blockHashes;

    error NotPusher();
    error UnknownParentBlockHash(uint256 parentBlockNumber);
    error PushedOutOfOrder(uint256 last, uint256 next);

    constructor() {
        aliasedPusher = AddressAliasHelper.applyL1ToL2Alias(address(new Pusher(address(this))));
    }

    function receiveHash(uint256 blockNumber, bytes32 blockHash) external {
        if (!isAuthorizedPusher(msg.sender)) revert NotPusher();

        // get the pointer position and the value at that position in the number buffer
        uint256 _bufferPtr = bufferPtr;
        uint256 valueAtPtr = blockNumberBuffer[_bufferPtr];

        // if we are overwriting a block number, delete its hash from the mapping
        if (valueAtPtr != 0) {
            blockHashes[valueAtPtr] = 0;

            // don't allow pushing out of order
            // QUESTION: early return or revert here?
            if (valueAtPtr >= blockNumber) {
                revert PushedOutOfOrder(valueAtPtr, blockNumber);
            }
        }

        // write the new block number into the buffer
        blockNumberBuffer[_bufferPtr] = blockNumber;

        // write the new hash into the mapping
        blockHashes[blockNumber] = blockHash;

        // increment the pointer
        bufferPtr = (_bufferPtr + 1) % bufferSize;

        // QUESTION: should we emit an event? 2935 does not
        // i think not, because it may not make sense to in a native solution
    }

    function parentBlockHash(uint256 parentBlockNumber) external view returns (bytes32) {
        bytes32 _parentBlockHash = blockHashes[parentBlockNumber];

        // QUESTION: should this revert or simply return 0?
        if (_parentBlockHash == 0) {
            revert UnknownParentBlockHash(parentBlockNumber);
        }

        return _parentBlockHash;
    }

    function isAuthorizedPusher(address account) public view returns (bool) {
        return account == aliasedPusher || ArbOwnerPublic(address(107)).isChainOwner(account);
    }
}

contract Pusher {
    bool public immutable isArbitrum;
    address public immutable bufferAddress;

    error WrongEthAmount(uint256 received, uint256 expected);

    constructor(address _bufferAddress) {
        bufferAddress = _bufferAddress;
        isArbitrum = ArbitrumChecker.isArbitrum();
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

        // QUESTION: emit an event?
    }
}
