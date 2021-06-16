// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./YearnV2StrategyBase.sol";

/**
 * Adds the mainnet vault addresses to the YearnV2StrategyBase
 */
contract YearnV2StrategyUSDC is YearnV2StrategyBase {
    string public constant override name = "YearnV2StrategyUSDC";
    string public constant override version = "V1";

    address internal constant _yvusdc =
        address(0x5f18C75AbDAe578b483E5F43f12a39cF75b973a9);

    // solhint-disable-next-line no-empty-blocks
    constructor(address _fund) public YearnV2StrategyBase(_fund, _yvusdc) {}
}
