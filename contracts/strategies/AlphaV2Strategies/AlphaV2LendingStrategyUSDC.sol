// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./AlphaV2LendingStrategyBase.sol";

/**
 * Adds the mainnet safebox addresses to the AlphaV2LendingStrategyBase
 */
contract AlphaV2LendingStrategyUSDC is AlphaV2LendingStrategyBase {
    string public constant override name = "AlphaV2LendingStrategyUSDC";
    string public constant override version = "V1";

    address internal constant _ibusdcv2 =
        address(0x08bd64BFC832F1C2B3e07e634934453bA7Fa2db2);

    constructor(address _fund)
        public
        AlphaV2LendingStrategyBase(_fund, _ibusdcv2)
    {}
}
