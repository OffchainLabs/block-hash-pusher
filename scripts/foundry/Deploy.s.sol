// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Buffer} from "contracts/Buffer.sol";

contract DeployScript is Script {
    function run() public {
        bytes32 salt = vm.envBytes32("CREATE2_SALT");
        address bufferAddress = vm.envAddress("EXPECTED_BUFFER_ADDRESS");
        address pusherAddress =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes2(0xd694), bufferAddress, bytes1(uint8(1)))))));
        if (bufferAddress.code.length != 0) {
            console.log("Already Deployed");
        } else {
            vm.startBroadcast();
            require(bufferAddress == address(new Buffer{salt: salt}()), "Buffer deployed to unexpected address");
            vm.stopBroadcast();
        }
        console.log("Buffer Address: ", bufferAddress);
        console.log("Pusher Address: ", pusherAddress);
    }
}
