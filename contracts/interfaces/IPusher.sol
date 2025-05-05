// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IPusher {
    /// @notice Emitted when block hashes are pushed to the buffer.
    /// @param  firstBlockNumber The block number of the first block in the batch.
    /// @param  lastBlockNumber The block number of the last block in the batch.
    event BlockHashesPushed(uint256 firstBlockNumber, uint256 lastBlockNumber);

    /// @notice Thrown when incorrect msg.value is provided
    error IncorrectMsgValue(uint256 expected, uint256 provided);

    /// @notice Thrown when the batch size is invalid.
    error InvalidBatchSize(uint256 batchSize);

    /// @notice Push some hashes of previous blocks to the buffer on the child chain specified by inbox
    /// @param inbox The address of the inbox on the child chain
    /// @param batchSize The number of hashes to push. Must be less than or equal to MAX_BATCH_SIZE. Must be at least 1.
    /// @param gasPriceBid The gas price bid for the transaction.
    /// @param gasLimit The gas limit for the transaction.
    /// @param submissionCost The cost of submitting the transaction.
    /// @param isERC20Inbox Whether the inbox is an ERC20 inbox.
    function pushHashes(
        address inbox,
        uint256 batchSize,
        uint256 gasPriceBid,
        uint256 gasLimit,
        uint256 submissionCost,
        bool isERC20Inbox
    ) external payable;

    /// @notice The max allowable number of hashes to push per call to pushHashes.
    function MAX_BATCH_SIZE() external view returns (uint256);

    /// @notice The address of the buffer contract on the child chain.
    function bufferAddress() external view returns (address);
    /// @notice Whether this contract is deployed on an Arbitrum chain.
    ///         This condition changes the way the block number is retrieved.
    function isArbitrum() external view returns (bool);
}
