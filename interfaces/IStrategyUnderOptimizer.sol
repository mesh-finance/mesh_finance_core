// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IStrategyUnderOptimizer {
    function aprAfterDeposit(uint256 depositAmount)
        external
        view
        returns (uint256);

    function apr() external view returns (uint256);
}
