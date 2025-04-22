// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IPusher {
    /// @notice Emitted when block hashes are pushed to the buffer.
    event BlockHashPushed(uint256 blockNumber);
    /// @notice Thrown when incorrect msg.value is provided

    error IncorrectMsgValue(uint256 expected, uint256 provided);

    /// @notice Thrown when the batch size is invalid.
    error InvalidBatchSize(uint256 batchSize);

    /// @notice Push the hash of the previous block to the buffer on the child chain specified by inbox
    /// @param inbox The address of the inbox on the child chain
    /// @param gasPriceBid The gas price bid for the transaction.
    /// @param gasLimit The gas limit for the transaction.
    /// @param submissionCost The cost of submitting the transaction.
    /// @param isERC20Inbox Whether the inbox is an ERC20 inbox.
    function pushHash(address inbox, uint256 gasPriceBid, uint256 gasLimit, uint256 submissionCost, bool isERC20Inbox)
        external
        payable;

    /// @notice The address of the buffer contract on the child chain.
    function bufferAddress() external view returns (address);
    /// @notice Whether this contract is deployed on an Arbitrum chain.
    ///         This condition changes the way the block number is retrieved.
    function isArbitrum() external view returns (bool);
}
