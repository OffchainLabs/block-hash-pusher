// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ArbSys} from "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";
import {ArbitrumChecker} from "@arbitrum/nitro-contracts/src/libraries/ArbitrumChecker.sol";
import {IInbox} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import {IERC20Inbox} from "@arbitrum/nitro-contracts/src/bridge/IERC20Inbox.sol";
import {IERC20Bridge} from "@arbitrum/nitro-contracts/src/bridge/IERC20Bridge.sol";
import {IBuffer} from "./interfaces/IBuffer.sol";
import {IPusher} from "./interfaces/IPusher.sol";

/// @notice The Pusher gets the hashes of some previous blocks and pushes them to the buffer on the child chain via retryable ticket.
contract Pusher is IPusher {
    using SafeERC20 for IERC20;

    /// @inheritdoc IPusher
    uint256 public constant MAX_BATCH_SIZE = 256;

    /// @inheritdoc IPusher
    bool public immutable isArbitrum;
    /// @inheritdoc IPusher
    address public immutable bufferAddress;

    constructor(address _bufferAddress) {
        bufferAddress = _bufferAddress;
        isArbitrum = ArbitrumChecker.runningOnArbitrum();
    }

    /// @inheritdoc IPusher
    function pushHashes(
        address inbox,
        uint256 batchSize,
        uint256 gasPriceBid,
        uint256 gasLimit,
        uint256 submissionCost,
        bool isERC20Inbox
    ) external payable {
        (uint256 firstBlockNumber, bytes32[] memory blockHashes) = _buildBlockHashArray(batchSize);

        if (isERC20Inbox) {
            // transfer tokens from the sender to the inbox to pay for the retryable ticket
            uint256 tokenTotalFeeAmount = gasLimit * gasPriceBid + submissionCost;
            if (tokenTotalFeeAmount > 0) {
                address token = IERC20Bridge(address(IERC20Inbox(inbox).bridge())).nativeToken();
                IERC20(token).safeTransferFrom(msg.sender, inbox, tokenTotalFeeAmount);
            }

            // create the retryable ticket
            IERC20Inbox(inbox).createRetryableTicket({
                to: bufferAddress,
                l2CallValue: 0,
                maxSubmissionCost: submissionCost,
                excessFeeRefundAddress: msg.sender,
                callValueRefundAddress: msg.sender,
                gasLimit: gasLimit,
                maxFeePerGas: gasPriceBid,
                data: abi.encodeCall(IBuffer.receiveHashes, (firstBlockNumber, blockHashes)),
                tokenTotalFeeAmount: tokenTotalFeeAmount
            });
        } else {
            // check that the msg.value is correct
            if (msg.value != gasLimit * gasPriceBid + submissionCost) {
                revert IncorrectMsgValue(gasLimit * gasPriceBid + submissionCost, msg.value);
            }

            // create the retryable ticket
            IInbox(inbox).createRetryableTicket{value: msg.value}({
                to: bufferAddress,
                l2CallValue: 0,
                maxSubmissionCost: submissionCost,
                excessFeeRefundAddress: msg.sender,
                callValueRefundAddress: msg.sender,
                gasLimit: gasLimit,
                maxFeePerGas: gasPriceBid,
                data: abi.encodeCall(IBuffer.receiveHashes, (firstBlockNumber, blockHashes))
            });
        }

        emit BlockHashesPushed(firstBlockNumber, firstBlockNumber + batchSize - 1);
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
