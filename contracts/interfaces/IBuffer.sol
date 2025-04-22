// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @notice This contract is a ring buffer that stores parent chain block hashes.
/// @dev    Other functions of a given implementation not included in this interface are not guaranteed to be stable.
///         The ring buffer is sparse, meaning the block numbers are not guaranteed to be contiguous.
///         A future version may or may not change the implementation of the ring buffer to be dense.
///         The size of the ring buffer may increase or decrease in future versions.
interface IBuffer {
    /// @notice Get a parent block hash given parent block number.
    /// @param parentBlockNumber The block number of the parent block.
    /// @return The block hash of the parent block.
    function parentBlockHash(uint256 parentBlockNumber) external view returns (bytes32);

    /// @dev Pushes some block hashes to the ring buffer. Can only be called by the aliased pusher contract or chain owners.
    ///      The last block in the buffer must be less than the last block being pushed.
    /// @param firstBlockNumber The block number of the first block in the batch.
    /// @param blockHashes The hashes of the blocks to be pushed. These are assumed to be in contiguous order.
    function receiveHashes(uint256 firstBlockNumber, bytes32[] calldata blockHashes) external;
}
