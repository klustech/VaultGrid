// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20ApproveOnly {
    function approve(address spender, uint256 amount) external returns (bool);
}
