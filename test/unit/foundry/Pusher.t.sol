// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";

import {Pusher} from "contracts/Pusher.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";
import {BufferPublic, Buffer} from "test/mocks/BufferPublic.sol";
import "test/mocks/MockArbSys.sol";

contract BaseTest is Test {
    address deployer = address(0xFFFF);
    BufferPublic buffer = BufferPublic(0xE5176a71F063744C55eC55e6D769e915E34FaD7D);
    Pusher pusher = Pusher(0x5ba7D5e27DFE1E52ccD096e25858424518cEd051);

    function _deploy() internal {
        vm.prank(deployer);
        new BufferPublic();
    }

    function _deployArbSys() internal {
        address arbSys = address(new MockArbSys());
        vm.etch(address(100), arbSys.code);
        MockArbSys(arbSys).arbOSVersion();
    }

    function testCorrectlyDeterminesIsArbitrum(bool isArbitrum) public {
        if (isArbitrum) _deployArbSys();
        _deploy();
        assertEq(pusher.isArbitrum(), isArbitrum);
    }

    function testContractsCorrectlyLinked(bool isArbitrum) public {
        if (isArbitrum) {
            _deployArbSys();
        }
        _deploy();
        assertEq(pusher.bufferAddress(), address(buffer));
        assertEq(buffer._aliasedPusher(), AddressAliasHelper.applyL1ToL2Alias(address(pusher)));
    }
}

contract BufferTest is BaseTest {
    function testAccessControl() public {
        _deploy();
        address rando = address(0x123);
        vm.expectRevert(Buffer.NotPusher.selector);
        vm.prank(rando);
        buffer.receiveHashes(0, new bytes32[](0));

        vm.prank(AddressAliasHelper.applyL1ToL2Alias(address(pusher)));
        buffer.receiveHashes(1, new bytes32[](1));

        vm.prank(buffer._systemPusher());
        buffer.receiveHashes(1, new bytes32[](2));
    }

    function testCanPushFirstItem() public {
        _deploy();
        _putItemsInBuffer(1, 1);

        assertEq(buffer._blockNumberBuffer(0), 1);
        assertEq(buffer._blockHashMapping(1), keccak256(abi.encode(1)));
    }

    function testCanPushFirstItems() public {
        _deploy();

        uint256 first = 10;
        uint256 len = 100;
        _putItemsInBuffer(first, len);

        for (uint256 i = 0; i < len; i++) {
            assertEq(buffer._blockNumberBuffer(i), first + i);
            assertEq(buffer._blockHashMapping(first + i), keccak256(abi.encode(first + i)));
            assertEq(buffer.parentBlockHash(first + i), keccak256(abi.encode(first + i)));
        }
    }

    function testBufferWrapsAround() public noGasMetering {
        _deploy();

        // fill everything but the last 10 items
        _putItemsInBuffer(1, buffer._bufferSize() - 10);

        // fill the last 10 items plus 10 more
        // this should overwrite the first 10 items
        _putItemsInBuffer(buffer._bufferSize() - 9, 20);

        for (uint256 i = 0; i < 10; i++) {
            uint256 eBlockNumber = buffer._bufferSize() + i + 1;

            // should overwrite the first 10 items
            assertEq(buffer._blockNumberBuffer(i), eBlockNumber);

            // should have set the block hash to the correct value
            assertEq(buffer._blockHashMapping(eBlockNumber), keccak256(abi.encode(eBlockNumber)));

            // should have evicted the old block hashes
            assertEq(buffer._blockHashMapping(i + 1), 0);
        }
    }

    function testUnknownBlockHash() public {
        _deploy();

        _putItemsInBuffer(1, 1);

        assertEq(buffer.parentBlockHash(1), keccak256(abi.encode(1)));
        vm.expectRevert(abi.encodeWithSelector(Buffer.UnknownParentBlockHash.selector, 2));
        buffer.parentBlockHash(2);
    }

    function testRangeValidityChecking() public {
        _deploy();

        // put some stuff in the buffer
        _putItemsInBuffer(1, 10);

        // cannot push zero length range
        vm.startPrank(buffer._systemPusher());
        vm.expectRevert(abi.encodeWithSelector(Buffer.InvalidBlockRange.selector, 10, 11, 0));
        buffer.receiveHashes(11, new bytes32[](0));

        // cannot push a range whose end <= the last item in the buffer
        // test <
        vm.expectRevert(abi.encodeWithSelector(Buffer.InvalidBlockRange.selector, 10, 5, 4));
        buffer.receiveHashes(5, new bytes32[](4));
        // test ==
        vm.expectRevert(abi.encodeWithSelector(Buffer.InvalidBlockRange.selector, 10, 5, 6));
        buffer.receiveHashes(5, new bytes32[](6));
        vm.stopPrank();

        // can push a range whose end > the last item in the buffer and start <= the last item in the buffer
        // test <
        _putItemsInBuffer(5, 7);
        // test ==
        _putItemsInBuffer(11, 2);

        for (uint256 i = 0; i < 12; i++) {
            assertEq(buffer._blockNumberBuffer(i), i + 1);
            assertEq(buffer._blockHashMapping(i + 1), keccak256(abi.encode(i + 1)));
        }

        // we can skip ahead and push a range that starts > the last item in the buffer
        _putItemsInBuffer(20, 2);
        assertEq(buffer._blockNumberBuffer(12), 20);
        assertEq(buffer._blockHashMapping(20), keccak256(abi.encode(20)));
        assertEq(buffer._blockNumberBuffer(13), 21);
        assertEq(buffer._blockHashMapping(21), keccak256(abi.encode(21)));
    }

    function _putItemsInBuffer(uint256 start, uint256 length) internal {
        bytes32[] memory hashes = new bytes32[](length);
        for (uint256 i = 0; i < length; i++) {
            hashes[i] = keccak256(abi.encode(start + i));
        }
        vm.prank(buffer._systemPusher());
        buffer.receiveHashes(start, hashes);
    }
}
