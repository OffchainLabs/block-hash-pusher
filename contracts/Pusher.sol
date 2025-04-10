// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ArbSys} from "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";
import {ArbitrumChecker} from "@arbitrum/nitro-contracts/src/libraries/ArbitrumChecker.sol";
import {IInbox} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import {IERC20Inbox} from "@arbitrum/nitro-contracts/src/bridge/IERC20Inbox.sol";
import {Buffer} from "./Buffer.sol";

/// @notice The Pusher gets the hash of the previous 256 blocks and pushes them to the buffer on the child chain via retryable ticket.
contract Pusher {
    /// @notice The number of hashes to push per transaction.
    uint256 public constant MAX_BATCH_SIZE = 256;

    /// @notice Whether this contract is deployed on an Arbitrum chain.
    ///         This condition changes the way the block number is retrieved.
    bool public immutable isArbitrum;
    /// @notice The address of the buffer contract on the child chain.
    address public immutable bufferAddress;

    /// @notice Emitted when block hashes are pushed to the buffer.
    event BlockHashesPushed(uint256 firstBlockNumber);

    /// @notice Thrown when incorrect msg.value is provided
    error IncorrectMsgValue(uint256 expected, uint256 provided);

    /// @notice Thrown when the batch size is invalid.
    error InvalidBatchSize(uint256 batchSize);

    constructor(address _bufferAddress) {
        bufferAddress = _bufferAddress;
        isArbitrum = ArbitrumChecker.runningOnArbitrum();
    }

    /// @notice Push the hash of the previous block to the buffer on the child chain specified by inbox
    ///         For custom fee chains, the caller must either set gasPriceBid, gasLimit, and submissionCost to 0 and manually redeem on the child,
    ///         or prefund the chain's inbox with the appropriate amount of fees.
    ///         (this is an [efficiency + implementation simplicity] vs [operator UX] tradeoff)
    /// @param inbox The address of the inbox on the child chain
    /// @param batchSize The number of hashes to push. Must be less than or equal to MAX_BATCH_SIZE. Must be at least 1.
    /// @param gasPriceBid The gas price bid for the transaction.
    /// @param gasLimit The gas limit for the transaction.
    /// @param submissionCost The cost of submitting the transaction.
    /// @param isERC20Inbox Whether the inbox is an ERC20 inbox.
    function pushHash(
        address inbox,
        uint256 batchSize, // todo: this should probably be removed and forced to 1. weird race conditions can come up with user choice
        uint256 gasPriceBid,
        uint256 gasLimit,
        uint256 submissionCost,
        bool isERC20Inbox
    ) external payable {
        (uint256 firstBlockNumber, bytes32[] memory blockHashes) = _buildBlockHashArray(batchSize);

        if (isERC20Inbox) {
            IERC20Inbox(inbox).createRetryableTicket({
                to: bufferAddress,
                l2CallValue: 0,
                maxSubmissionCost: submissionCost,
                excessFeeRefundAddress: msg.sender,
                callValueRefundAddress: msg.sender,
                gasLimit: gasLimit,
                maxFeePerGas: gasPriceBid,
                data: abi.encodeCall(Buffer.receiveHashes, (firstBlockNumber, blockHashes)),
                tokenTotalFeeAmount: gasLimit * gasPriceBid + submissionCost
            });
        } else {
            if (msg.value != gasLimit * gasPriceBid + submissionCost) {
                revert IncorrectMsgValue(gasLimit * gasPriceBid + submissionCost, msg.value);
            }
            IInbox(inbox).createRetryableTicket{value: msg.value}({
                to: bufferAddress,
                l2CallValue: 0,
                maxSubmissionCost: submissionCost,
                excessFeeRefundAddress: msg.sender,
                callValueRefundAddress: msg.sender,
                gasLimit: gasLimit,
                maxFeePerGas: gasPriceBid,
                data: abi.encodeCall(Buffer.receiveHashes, (firstBlockNumber, blockHashes))
            });
        }

        emit BlockHashesPushed(firstBlockNumber);
    }

    /// @dev Build an array of the last 256 block hashes
    function _buildBlockHashArray(uint256 batchSize)
        internal
        view
        returns (uint256 firstBlockNumber, bytes32[] memory blockHashes)
    {
        if (batchSize == 0 || batchSize > MAX_BATCH_SIZE) {
            revert InvalidBatchSize(batchSize);
        }

        blockHashes = new bytes32[](batchSize);

        if (isArbitrum) {
            firstBlockNumber = ArbSys(address(100)).arbBlockNumber() - batchSize;
            for (uint256 i = 0; i < batchSize; i++) {
                blockHashes[i] = ArbSys(address(100)).arbBlockHash(firstBlockNumber + i);
            }
        } else {
            firstBlockNumber = block.number - batchSize;
            for (uint256 i = 0; i < batchSize; i++) {
                blockHashes[i] = blockhash(firstBlockNumber + i);
            }
        }
    }
}
