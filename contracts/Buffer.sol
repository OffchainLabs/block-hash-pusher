// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IBuffer} from "./interfaces/IBuffer.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";
import {Pusher} from "./Pusher.sol";

/// @notice An implementation of the IBuffer interface.
/// @dev    This contract is deployed with CREATE2 on all chains to the same address.
///         This contract's bytecode may or may not be overwritten in a future ArbOS upgrade.
contract Buffer is IBuffer {
    /// @inheritdoc IBuffer
    uint256 public constant bufferSize = 393168;

    /// @inheritdoc IBuffer
    address public constant systemPusher = address(0xA4B05); // todo: choose a good address for this

    /// @inheritdoc IBuffer
    address public immutable aliasedPusher;

    /// @inheritdoc IBuffer
    bool public systemHasPushed;

    uint248 firstBlockInBuffer = 0;

    /// @inheritdoc IBuffer
    mapping(uint256 => bytes32) public blockHashMapping;

    constructor() {
        aliasedPusher = AddressAliasHelper.applyL1ToL2Alias(address(new Pusher(address(this))));
    }

    /// @inheritdoc IBuffer
    function parentBlockHash(uint256 parentBlockNumber) external view returns (bytes32) {
        bytes32 _parentBlockHash = blockHashMapping[parentBlockNumber];

        // QUESTION: should this revert or simply return 0?
        if (_parentBlockHash == 0) {
            revert UnknownParentBlockHash(parentBlockNumber);
        }

        return _parentBlockHash;
    }

    /// @inheritdoc IBuffer
    function receiveHashes(uint256 firstBlockNumber, bytes32[] calldata blockHashes) external {
        if (blockHashes.length == 0) {
            revert("no hashes");
        }
        if (blockHashes.length > bufferSize) {
            revert("too many hashes");
        }
        if (firstBlockNumber + blockHashes.length < firstBlockInBuffer) {
            revert("block too late");
        }

        // check caller authorization
        if (systemHasPushed) {
            // if the system has pushed, only the system can push
            if (msg.sender != systemPusher) {
                revert NotPusher();
            }
        } else if (msg.sender == systemPusher) {
            // if the system has not previously pushed, and is pushing now, set the flag
            systemHasPushed = true;
        } else if (msg.sender != aliasedPusher) {
            // the caller is neither the system pusher nor the aliased pusher
            revert NotPusher();
        }

        uint256 _firstBlockInBuffer = firstBlockInBuffer;

        if (firstBlockNumber < _firstBlockInBuffer) {
            revert("block too early");
        }

        // see if we must evict from mapping and update firstBlockInBuffer
        if (firstBlockNumber + blockHashes.length > _firstBlockInBuffer + bufferSize) {
            uint256 countToEvict = firstBlockNumber + blockHashes.length - (_firstBlockInBuffer + bufferSize);
            for (uint256 i = 0; i < countToEvict; i++) {
                blockHashMapping[_firstBlockInBuffer + i] = 0;
            }
            firstBlockInBuffer = uint248(_firstBlockInBuffer + bufferSize);
        }

        // fill the buffer with the new hashes
        for (uint256 i = 0; i < blockHashes.length; i++) {
            blockHashMapping[firstBlockNumber + i] = blockHashes[i];
        }
    }
}
