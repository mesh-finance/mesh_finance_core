// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./SushiBarStrategyBase.sol";

/**
 * Adds the mainnet vault addresses to the YearnV2StrategyBase
 */
contract SushiBarStrategySUSHI is SushiBarStrategyBase {
    string public constant name = "SushiBarStrategyUSDC";
    string public constant version = "V1";

    address internal constant _sushi =
        address(0x6B3595068778DD592e39A122f4f5a5cF09C90fE2);

    constructor(address _fund) public SushiBarStrategyBase(_fund, _sushi) {}
}
