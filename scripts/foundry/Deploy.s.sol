// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Buffer} from "contracts/Buffer.sol";

contract DeployScript is Script {
    function run() public {
        vm.startBroadcast();
        new Buffer{salt: vm.envBytes32("CREATE2_SALT")}();
        vm.stopBroadcast();
    }
}
