// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @notice This contract is a buffer that stores parent chain block hashes.
/// @dev    Everything in this interface besides parentChainBlockHash(uint256) is not guaranteed to be stable.
///         The buffer is sparse, meaning the block numbers are not guaranteed to be contiguous.
///         A future version may or may not change the implementation of the buffer to be dense.
///         The size of the buffer may increase or decrease in future versions.
///         Once a block X is included in the buffer, it will remain available
///         until another block X+M*bufferSize is pushed, where M is a positive integer.
interface IBuffer {
    /// @notice Emitted when the buffer is pushed to. Does not guarantee that the block hashes were included in the buffer.
    /// @param  firstBlockNumber The block number of the first block in the batch.
    /// @param  lastBlockNumber The block number of the last block in the batch.
    event BlockHashesPushed(uint256 firstBlockNumber, uint256 lastBlockNumber);

    /// @notice Thrown by `parentChainBlockHash` when the block hash for a given block number is not found.
    error UnknownParentChainBlockHash(uint256 parentChainBlockNumber);

    /// @dev Thrown when the caller is not authorized to push hashes.
    error NotPusher();

    /// @dev Pushes some block hashes to the buffer. Can only be called by the aliased pusher contract or chain owners.
    ///      The last block in the buffer must be less than the last block being pushed.
    /// @param firstBlockNumber The block number of the first block in the batch.
    /// @param blockHashes The hashes of the blocks to be pushed. These are assumed to be in contiguous order.
    function receiveHashes(uint256 firstBlockNumber, bytes32[] memory blockHashes) external;

    /// @notice Get a parent chain block hash given parent chain block number. Guaranteed to be stable.
    /// @param  parentChainBlockNumber The block number of the parent chain block.
    /// @return The block hash of the parent chain block.
    function parentChainBlockHash(uint256 parentChainBlockNumber) external view returns (bytes32);

    /// @notice The highest block number that has been pushed
    function newestBlockNumber() external view returns (uint64);

    /// @dev 393168 - the size of the buffer. This is the maximum number of block hashes that can be stored.
    ///      For a parent chain with a block time of 250ms, this is equivalent to roughly 27 hours of history,
    ///      which is the same amount of time that EIP-2935 covers for L1 block hashes.
    ///      For a parent chain with a block time of 12s, this is equivalent to roughly 54 days of history.
    ///      For example, Arbitrum One has L1 as the parent, so the Buffer deployed to Arbitrum One will cover ~54 days of L1 history.
    function bufferSize() external view returns (uint256);
    /// @dev A system address that is authorized to push hashes to the buffer.
    function systemPusher() external view returns (address);
    /// @dev The aliased address of the pusher contract on the parent chain.
    function aliasedPusher() external view returns (address);
    /// @dev Maps block numbers to their hashes. This is a mapping of block number to block hash.
    ///      Block hashes are deleted from the mapping when they are overwritten in the ring buffer.
    function blockHashMapping(uint256) external view returns (bytes32);
    /// @dev A buffer of block numbers whose hashes are stored in the `blockHashes` mapping.
    ///      Should be the last storage variable declared to maintain flexibility in resizing the buffer.
    function blockNumberBuffer(uint256) external view returns (uint256);
    /// @dev Whether the system address has pushed a block hash to the buffer.
    ///      Once this is set, only the system address can push more hashes.
    function systemHasPushed() external view returns (bool);
}
