// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {Buffer, IBuffer} from "contracts/Buffer.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";
import {BaseTest} from "test/unit/foundry/BaseTest.t.sol";

contract BufferTest is BaseTest {
    uint256 highestBlockNumber = 0;

    function setUp() public {
        highestBlockNumber = 0;
    }

    function testAccessControl() public {
        _deploy();
        address rando = address(0x123);
        vm.expectRevert(IBuffer.NotPusher.selector);
        vm.prank(rando);
        buffer.receiveHashes(1, new bytes32[](1));

        vm.prank(AddressAliasHelper.applyL1ToL2Alias(address(pusher)));
        buffer.receiveHashes(1, new bytes32[](1));

        vm.prank(buffer.systemPusher());
        buffer.receiveHashes(2, new bytes32[](1));
    }

    function testCanPushFirstItem() public {
        _deploy();
        _putItemsInBuffer(1, 1);

        _shouldHave(1);
    }

    function testCanPushFirstItems() public {
        _deploy();

        uint256 first = 10;
        uint256 len = 100;
        _putItemsInBuffer(first, len);

        for (uint256 i = 0; i < len; i++) {
            _shouldHave(first + i);
        }
    }

    function testBufferWrapsAround() public noGasMetering {
        _deploy();

        // fill everything but the last 10 items
        _putItemsInBuffer(1, buffer.bufferSize() - 10);

        // fill the last 10 items plus 10 more
        // this should overwrite the first 10 items
        _putItemsInBuffer(buffer.bufferSize() - 9, 20);

        for (uint256 i = 0; i < 10; i++) {
            uint256 eBlockNumber = buffer.bufferSize() + i + 1;

            // should overwrite the first 10 items
            // should have set the block hash to the correct value
            _shouldHave(eBlockNumber);

            // should have evicted the old block hashes
            _shouldNotHave(i + 1);
        }
    }

    function testUnknownBlockHash() public {
        _deploy();

        _putItemsInBuffer(1, 1);

        _shouldHave(1);
        _shouldNotHave(2);
    }

    function testCannotOverwriteNewerBlocks() public {
        _deploy();

        // fill the buffer with 10 items
        _putItemsInBuffer(buffer.bufferSize(), 10);

        // try to overwrite the first 5 items
        _putItemsInBuffer(1, 5);

        // should retain the later blocks
        for (uint256 i = 0; i < 10; i++) {
            _shouldHave(buffer.bufferSize() + i);
        }
    }

    function testOutOfOrderPush() public {
        _deploy();

        // fill 10-20
        _putItemsInBuffer(10, 10);

        // fill 5-15
        _putItemsInBuffer(5, 10);

        // should have 5-20
        for (uint256 i = 5; i < 20; i++) {
            _shouldHave(i);
        }
        _shouldNotHave(4);
        _shouldNotHave(21);
    }

    function testSystemPusherTakeover() public {
        _deploy();

        // fill the buffer with 10 items
        _putItemsInBuffer(1, 10, false);

        assertFalse(buffer.systemHasPushed());

        // fill the buffer with 10 items using the system pusher
        _putItemsInBuffer(11, 10, true);

        assertTrue(buffer.systemHasPushed());

        // make sure everything was put in properly
        for (uint256 i = 0; i < 20; i++) {
            _shouldHave(i + 1);
        }

        // try to use the aliased pusher to push more items, should fail
        vm.expectRevert(IBuffer.NotPusher.selector);
        vm.prank(AddressAliasHelper.applyL1ToL2Alias(address(pusher)));
        buffer.receiveHashes(21, new bytes32[](10));

        // try to use the system pusher to push more items, should work
        _putItemsInBuffer(21, 10, true);
    }

    function _putItemsInBuffer(uint256 start, uint256 length) internal {
        _putItemsInBuffer(start, length, false);
    }

    function _putItemsInBuffer(uint256 start, uint256 length, bool useSystem) internal {
        assertEq(buffer.newestBlockNumber(), highestBlockNumber);

        bytes32[] memory hashes = new bytes32[](length);
        for (uint256 i = 0; i < length; i++) {
            hashes[i] = keccak256(abi.encode(start + i));
        }
        vm.prank(useSystem ? buffer.systemPusher() : AddressAliasHelper.applyL1ToL2Alias(address(pusher)));
        vm.expectEmit(true, false, false, true, address(buffer));
        emit IBuffer.BlockHashesPushed(start, start + length - 1);
        buffer.receiveHashes(start, hashes);

        assertEq(buffer.newestBlockNumber(), _max(highestBlockNumber, start + length - 1));
        highestBlockNumber = buffer.newestBlockNumber();
    }

    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function _shouldHave(uint256 blockNumber) internal {
        assertEq(buffer.parentChainBlockHash(blockNumber), keccak256(abi.encode(blockNumber)));
        assertEq(buffer.blockNumberBuffer(blockNumber % buffer.bufferSize()), blockNumber);
    }

    function _shouldNotHave(uint256 blockNumber) internal {
        vm.expectRevert(abi.encodeWithSelector(IBuffer.UnknownParentChainBlockHash.selector, blockNumber));
        buffer.parentChainBlockHash(blockNumber);
    }
}
