// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Buffer} from "contracts/Buffer.sol";

/// @notice Extend Buffer to expose otherwise internal functions and state variables.
contract BufferPublic is Buffer {
    function _bufferSize() external pure returns (uint256) {
        return bufferSize;
    }

    function _aliasedPusher() external view returns (address) {
        return aliasedPusher;
    }

    function _systemPusher() external pure returns (address) {
        return systemPusher;
    }

    function _blockNumberBuffer(uint256 index) external view returns (BufferItem memory) {
        return blockNumberBuffer[index];
    }

    function _blockNumberBufferLength() external view returns (uint256) {
        return blockNumberBuffer.length;
    }

    function _bufferPtr() external view returns (uint256) {
        return bufferPtr;
    }

    function _blockHashMapping(uint256 blockNumber) external view returns (bytes32) {
        return blockHashMapping[blockNumber];
    }
}
