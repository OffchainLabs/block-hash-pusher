// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";

import "contracts/Pusher.sol";
import "test/mocks/MockArbSys.sol";

contract PusherTest is Test {
    address deployer = address(0xFFFF);
    Buffer buffer = Buffer(0xE5176a71F063744C55eC55e6D769e915E34FaD7D);
    Pusher pusher = Pusher(0x5ba7D5e27DFE1E52ccD096e25858424518cEd051);

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
        assertEq(buffer.aliasedPusher(), AddressAliasHelper.applyL1ToL2Alias(address(pusher)));
    }

    function _deploy() public {
        vm.prank(deployer);
        new Buffer();
    }

    function _deployArbSys() public {
        address arbSys = address(new MockArbSys());
        vm.etch(address(100), arbSys.code);
        MockArbSys(arbSys).arbOSVersion();
    }
}
