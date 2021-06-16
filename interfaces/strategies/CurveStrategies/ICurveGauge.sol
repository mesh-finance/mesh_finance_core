// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface ICurveGauge {
    function claimable_tokens(address user) external returns (uint256);

    function claimable_reward(address user, address token)
        external
        returns (uint256);

    function claim_rewards(address user) external;

    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;
}
