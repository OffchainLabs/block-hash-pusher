// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ArbSys} from "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";
import {ArbitrumChecker} from "@arbitrum/nitro-contracts/src/libraries/ArbitrumChecker.sol";
import {IInbox} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import {Buffer} from "./Buffer.sol";

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
