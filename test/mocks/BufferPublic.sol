// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Buffer} from "contracts/Pusher.sol";

/// @notice Extend Buffer to expose otherwise internal functions and state variables.
contract BufferPublic is Buffer {
    function _bufferSize() external pure returns (uint256) {
        return bufferSize;
    }
    function _aliasedPusher() external view returns (address) {
        return aliasedPusher;
    }
    function _blockNumberBuffer(uint index) external view returns (uint256) {
        return blockNumberBuffer[index];
    }
    function _blockNumberBufferLength() external view returns (uint256) {
        return blockNumberBuffer.length;
    }
    function _bufferPtr() external view returns (uint256) {
        return bufferPtr;
    }
    function _blockHashes(uint256 blockNumber) external view returns (bytes32) {
        return blockHashes[blockNumber];
    }
}