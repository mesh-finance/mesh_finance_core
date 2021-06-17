// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./BentoBoxStrategyBase.sol";

/**
 * Adds the mainnet vault addresses to the YearnV2StrategyBase
 */
contract BentoBoxStrategyUSDC is BentoBoxStrategyBase {
    string public constant name = "BentoBoxStrategyUSDC";
    string public constant version = "V1";

    address internal constant _usdc =
        address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    constructor(address _fund) public BentoBoxStrategyBase(_fund, _usdc) {}
}
