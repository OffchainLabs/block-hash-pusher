// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";

import {Pusher} from "contracts/Pusher.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";
import {BufferPublic} from "test/mocks/BufferPublic.sol";
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
}

contract BufferTest is BaseTest {
    error NotPusher();
    function testAccessControl() public {
        _deploy();
        address rando = address(0x123);
        vm.expectRevert(NotPusher.selector);
        vm.prank(rando);
        buffer.receiveHashes(0, new bytes32[](0));

        vm.prank(AddressAliasHelper.applyL1ToL2Alias(address(pusher)));
        buffer.receiveHashes(1, new bytes32[](1));

        vm.prank(buffer._systemPusher());
        buffer.receiveHashes(1, new bytes32[](2));
    }

}

contract PusherTest is BaseTest {
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
