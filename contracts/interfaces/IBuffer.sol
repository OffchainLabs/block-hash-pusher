// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @notice This contract is a ring buffer that stores parent chain block hashes.
/// @dev    All functions in this interface besides parentBlockHash(uint256) are not guaranteed to be stable.
///         The ring buffer is sparse, meaning the block numbers are not guaranteed to be contiguous.
///         A future version may or may not change the implementation of the ring buffer to be dense.
///         The size of the ring buffer may increase or decrease in future versions.
interface IBuffer {
    /// @notice Thrown by `parentBlockHash` when the block hash for a given block number is not found.
    error UnknownParentBlockHash(uint256 parentBlockNumber);
    /// @dev Thrown when the caller is not authorized to push hashes.
    error NotPusher();

    /// @dev Pushes some block hashes to the ring buffer. Can only be called by the aliased pusher contract or chain owners.
    ///      The last block in the buffer must be less than the last block being pushed.
    /// @param firstBlockNumber The block number of the first block in the batch.
    /// @param blockHashes The hashes of the blocks to be pushed. These are assumed to be in contiguous order.
    function receiveHashes(uint256 firstBlockNumber, bytes32[] memory blockHashes) external;

    /// @notice Get a parent block hash given parent block number. Guaranteed to be stable.
    /// @param parentBlockNumber The block number of the parent block.
    /// @return The block hash of the parent block.
    function parentBlockHash(uint256 parentBlockNumber) external view returns (bytes32);

    /// @dev The size of the ring buffer. This is the maximum number of block hashes that can be stored.
    ///      Assuming a parent block time of 250ms and L1 block time of 12s,
    ///      then the amount of time that the buffer covers is equivalent to EIP-2935's.
    function bufferSize() external view returns (uint256);
    /// @dev A system address that is authorized to push hashes to the buffer.
    function systemPusher() external view returns (address);
    /// @dev The aliased address of the pusher contract on the parent chain.
    function aliasedPusher() external view returns (address);
    /// @dev Maps block numbers to their hashes. This is a mapping of block number to block hash.
    ///      Block hashes are deleted from the mapping when they are overwritten in the ring buffer.
    function blockHashMapping(uint256) external view returns (bytes32);
    /// @dev A ring buffer of block numbers whose hashes are stored in the `blockHashes` mapping.
    ///      Should be the last storage variable declared to maintain flexibility in resizing the buffer.
    function blockNumberBuffer(uint256) external view returns (uint256);
    /// @dev Whether the system address has pushed a block hash to the buffer.
    ///         Once this is set, only the system address can push more hashes.
    function systemHasPushed() external view returns (bool);
}
