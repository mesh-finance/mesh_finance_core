// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./AaveV2LendingStrategyBase.sol";

/**
 * Adds the polygon mainnet addresses to the AaveV2LendingStrategyBase
 */
contract AaveV2LendingStrategyPolygonMainnet is AaveV2LendingStrategyBase {
    string public constant override name =
        "AaveV2LendingStrategyPolygonMainnet";
    string public constant override version = "V1";

    // Address provider for AAVE
    address internal constant _aaveAddressProvider =
        address(0xd05e3E715d945B59290df0ae8eF85c1BdB684744);

    // Incentive Controller for rewards
    address internal constant _incentivesController =
        address(0x357D51124f59836DeD84c8a1730D72B749d8BC23);

    // MATIC token as rewards
    address internal constant MATIC =
        address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

    // Quickswap (Uniswap V2 fork) router to liquidate MATIC rewards to underlying
    address internal constant _quickswapRouter =
        address(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);

    constructor(address _fund)
        public
        AaveV2LendingStrategyBase(
            _fund,
            _aaveAddressProvider,
            _incentivesController,
            MATIC,
            MATIC,
            _quickswapRouter,
            MATIC
        )
    // solhint-disable-next-line no-empty-blocks
    {

    }
}
