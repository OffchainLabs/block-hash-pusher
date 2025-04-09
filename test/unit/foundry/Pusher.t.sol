// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {BaseTest} from "./BaseTest.t.sol";

import {IInbox} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import {ArbSys} from "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";
import {Buffer} from "contracts/Buffer.sol";
import {MockInbox} from "test/mocks/MockInbox.sol";
// todo: test eth amounts

contract PusherTest is BaseTest {
    uint256 constant rollTo = 500;

    function setUp() public {
        vm.roll(rollTo);
    }

    function testPushesOnArb() public {
        _deployArbSys();
        _deploy();
        bytes32[] memory blockHashes = new bytes32[](256);
        uint256 arbBlockNum = ArbSys(address(100)).arbBlockNumber();
        for (uint256 i = 0; i < 256; i++) {
            blockHashes[i] = ArbSys(address(100)).arbBlockHash(arbBlockNum - 256 + i);
        }
        _push(0, 0, 0, abi.encodeCall(Buffer.receiveHashes, (arbBlockNum - 256, blockHashes)));
    }

    function testPushesOnNonArb() public {
        _deploy();
        bytes32[] memory blockHashes = new bytes32[](256);
        for (uint256 i = 0; i < 256; i++) {
            blockHashes[i] = blockhash(rollTo - 256 + i);
        }
        _push(0, 0, 0, abi.encodeCall(Buffer.receiveHashes, (rollTo - 256, blockHashes)));
    }

    function _push(uint256 gasPriceBid, uint256 gasLimit, uint256 submissionCost, bytes memory expectedBufferCalldata)
        internal
    {
        address mockInbox = address(new MockInbox());
        address caller = address(0x5678);

        bytes memory expectedInboxCalldata = abi.encodeCall(
            IInbox.createRetryableTicket,
            (address(buffer), 0, submissionCost, caller, caller, gasLimit, gasPriceBid, expectedBufferCalldata)
        );
        vm.prank(caller);
        vm.expectCall(mockInbox, gasPriceBid * gasLimit + submissionCost, expectedInboxCalldata, 1);
        // vm.breakpoint("a");
        pusher.pushHash{value: gasPriceBid * gasLimit + submissionCost}({
            inbox: mockInbox,
            gasPriceBid: gasPriceBid,
            gasLimit: gasLimit,
            submissionCost: submissionCost,
            isERC20Inbox: false
        });
    }
}
