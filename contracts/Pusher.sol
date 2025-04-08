// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ArbSys} from "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";
import {ArbitrumChecker} from "@arbitrum/nitro-contracts/src/libraries/ArbitrumChecker.sol";
import {IInbox} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import {Buffer} from "./Buffer.sol";

/// @notice The Pusher gets the hash of the previous 256 blocks and pushes them to the buffer on the child chain via retryable ticket.
contract Pusher {
    /// @notice Whether this contract is deployed on an Arbitrum chain.
    ///         This condition changes the way the block number is retrieved.
    bool public immutable isArbitrum;
    /// @notice The address of the buffer contract on the child chain.
    address public immutable bufferAddress;

    /// @notice Emitted when block hashes are pushed to the buffer.
    event BlockHashesPushed(uint256 firstBlockNumber);

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
        if (gasPriceBid * gasLimit + submissionCost != msg.value) {
            revert WrongEthAmount(msg.value, gasPriceBid * gasLimit + submissionCost);
        }

        (uint256 firstBlockNumber, bytes32[] memory blockHashes) = _buildBlockHashArray();

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

        emit BlockHashesPushed(firstBlockNumber);
    }

    /// @dev Build an array of the last 256 block hashes
    function _buildBlockHashArray() internal view returns (uint256 firstBlockNumber, bytes32[] memory blockHashes) {
        blockHashes = new bytes32[](256);
        if (isArbitrum) {
            firstBlockNumber = ArbSys(address(100)).arbBlockNumber() - 256;
            for (uint256 i = 0; i < 256; i++) {
                blockHashes[i] = ArbSys(address(100)).arbBlockHash(firstBlockNumber + i);
            }
        }
        else {
            firstBlockNumber = block.number - 256;
            for (uint256 i = 0; i < 256; i++) {
                blockHashes[i] = blockhash(firstBlockNumber + i);
            }
        }
    }
}
