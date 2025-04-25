// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {Buffer, IBuffer} from "contracts/Buffer.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";
import {BaseTest} from "test/unit/foundry/BaseTest.t.sol";

contract BufferTest is BaseTest {
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

        _shouldHaveAtIndex(1, 0);
    }

    function testCanPushFirstItems() public {
        _deploy();

        uint256 first = 10;
        uint256 len = 100;
        _putItemsInBuffer(first, len);

        for (uint256 i = 0; i < len; i++) {
            _shouldHaveAtIndex(first + i, i);
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
            _shouldHaveAtIndex(eBlockNumber, i);

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

    function testRangeValidityChecking() public {
        _deploy();

        // put some stuff in the buffer
        _putItemsInBuffer(1, 10);

        // cannot push zero length range
        vm.startPrank(buffer.systemPusher());
        vm.expectRevert(); // todo
        buffer.receiveHashes(11, new bytes32[](0));

        // cannot push a range whose end <= the last item in the buffer
        // test <
        vm.expectRevert(); // todo
        buffer.receiveHashes(5, new bytes32[](4));
        // test ==
        vm.expectRevert(); // todo
        buffer.receiveHashes(5, new bytes32[](6));
        vm.stopPrank();

        // can push a range whose end > the last item in the buffer and start <= the last item in the buffer
        // test <
        _putItemsInBuffer(5, 7);
        // test ==
        _putItemsInBuffer(11, 2);

        for (uint256 i = 0; i < 12; i++) {
            _shouldHaveAtIndex(i + 1, i);
        }

        // we can skip ahead and push a range that starts > the last item in the buffer
        _putItemsInBuffer(20, 2);
        _shouldHaveAtIndex(20, 12);
        _shouldHaveAtIndex(21, 13);
        _shouldNotHave(22);
        _shouldNotHave(19);
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
            _shouldHaveAtIndex(i + 1, i);
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
        bytes32[] memory hashes = new bytes32[](length);
        for (uint256 i = 0; i < length; i++) {
            hashes[i] = keccak256(abi.encode(start + i));
        }
        vm.prank(useSystem ? buffer.systemPusher() : AddressAliasHelper.applyL1ToL2Alias(address(pusher)));
        buffer.receiveHashes(start, hashes);
    }

    function _shouldHave(uint256 blockNumber) internal {
        assertEq(buffer.parentBlockHash(blockNumber), keccak256(abi.encode(blockNumber)));
    }

    function _shouldHaveAtIndex(uint256 blockNumber, uint256 index) internal {
        _shouldHave(blockNumber);
        // assertEq(buffer.blockNumberBuffer(index), blockNumber);
    }

    function _shouldNotHave(uint256 blockNumber) internal {
        vm.expectRevert(abi.encodeWithSelector(IBuffer.UnknownParentBlockHash.selector, blockNumber));
        buffer.parentBlockHash(blockNumber);
    }
}
