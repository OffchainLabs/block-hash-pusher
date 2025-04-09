// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

contract MockArbSys {
    function arbOSVersion() external pure returns (uint256) {
        return 1;
    }

    function arbBlockNumber() external pure returns (uint256) {
        return 1000;
    }

    function arbBlockHash(uint256 blockNumber) external pure returns (bytes32) {
        if (blockNumber + 256 < 1000) revert("invalid block number for ArbBlockHAsh");
        return keccak256(abi.encode(blockNumber));
    }
}
