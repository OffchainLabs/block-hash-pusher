// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

contract MockInbox {
    function createRetryableTicket(address, uint256, uint256, address, address, uint256, uint256, bytes calldata)
        external
        payable
        returns (uint256)
    {
        return 1;
    }
}
