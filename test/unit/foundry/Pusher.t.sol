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
        uint256 batchSize = 256;
        bytes32[] memory blockHashes = new bytes32[](batchSize);
        uint256 arbBlockNum = ArbSys(address(100)).arbBlockNumber();
        for (uint256 i = 0; i < batchSize; i++) {
            blockHashes[i] = ArbSys(address(100)).arbBlockHash(arbBlockNum - batchSize + i);
        }
        _push(batchSize, 0, 0, 0, abi.encodeCall(Buffer.receiveHashes, (arbBlockNum - batchSize, blockHashes)));
    }

    function testPushesOnNonArb() public {
        _deploy();
        uint256 batchSize = 100;
        bytes32[] memory blockHashes = new bytes32[](batchSize);
        for (uint256 i = 0; i < batchSize; i++) {
            blockHashes[i] = blockhash(rollTo - batchSize + i);
        }
        _push(batchSize, 0, 0, 0, abi.encodeCall(Buffer.receiveHashes, (rollTo - batchSize, blockHashes)));
    }

    function _push(
        uint256 batchSize,
        uint256 gasPriceBid,
        uint256 gasLimit,
        uint256 submissionCost,
        bytes memory expectedBufferCalldata
    ) internal {
        address mockInbox = address(new MockInbox());
        address caller = address(0x5678);

        bytes memory expectedInboxCalldata = abi.encodeCall(
            IInbox.createRetryableTicket,
            (address(buffer), 0, submissionCost, caller, caller, gasLimit, gasPriceBid, expectedBufferCalldata)
        );
        vm.prank(caller);
        vm.expectCall(mockInbox, gasPriceBid * gasLimit + submissionCost, expectedInboxCalldata, 1);
        pusher.pushHashes{value: gasPriceBid * gasLimit + submissionCost}({
            inbox: mockInbox,
            batchSize: batchSize,
            gasPriceBid: gasPriceBid,
            gasLimit: gasLimit,
            submissionCost: submissionCost,
            isERC20Inbox: false
        });
    }
}
