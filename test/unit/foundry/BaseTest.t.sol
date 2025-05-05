// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {Pusher} from "contracts/Pusher.sol";
import {Buffer} from "contracts/Buffer.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";
import {MockArbSys} from "test/mocks/MockArbSys.sol";

contract BaseTest is Test {
    address deployer = address(0xFFFF);
    Buffer buffer = Buffer(0xE5176a71F063744C55eC55e6D769e915E34FaD7D);
    Pusher pusher = Pusher(0x5ba7D5e27DFE1E52ccD096e25858424518cEd051);

    function _deploy() internal {
        vm.prank(deployer);
        new Buffer();
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
        assertEq(buffer.aliasedPusher(), AddressAliasHelper.applyL1ToL2Alias(address(pusher)));
    }
}
