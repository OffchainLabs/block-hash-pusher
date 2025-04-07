// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @notice This contract is a ring buffer that stores parent chain block hashes.
/// @dev    This is the guaranteed, public interface for the buffer contract. Future versions may add more functions.
///         Other functions of a given implementation not included in this interface are not guaranteed to be stable.
///         The ring buffer is sparse, meaning the block numbers are not guaranteed to be contiguous.
///         A future version may or may not change the implementation of the ring buffer to be dense.
///         The size of the ring buffer may increase or decrease in future versions.
interface IBuffer {
    function parentBlockHash(uint256 parentBlockNumber) external view returns (bytes32);
}
