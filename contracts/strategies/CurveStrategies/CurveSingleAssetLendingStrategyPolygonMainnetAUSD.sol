// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./CurveSingleAssetLendingStrategyBase.sol";

/**
 * Adds the polygon mainnet addresses to the CurveSingleAssetLendingStrategyBase
 */
contract CurveSingleAssetLendingStrategyPolygonMainnetAUSD is
    CurveSingleAssetLendingStrategyBase
{
    string public constant override name =
        "CurveSingleAssetLendingStrategyPolygonMainnetAUSD";
    string public constant override version = "V1";

    // Required Curve Pool (aave USD)
    address internal constant _crvPool =
        address(0x445FE580eF8d70FF569aB36e80c647af338db351);

    // Corresponding curve pool token (am3crv)
    address internal constant _crvPoolToken =
        address(0xE7a24EF0C5e95Ffb0f6684b813A78F2a3AD7D171);

    // Gauge for rewards
    address internal constant _crvPoolGauge =
        address(0xe381C25de995d62b453aF8B931aAc84fcCaa7A62);

    // Gauge type. Rewards: {1: Only CRV, 2: CRV + Reward, 3: Only Reward}
    uint8 internal constant _crvPoolGaugeType = 3;

    // CRV token as rewards, None in this case
    address internal constant _CRVToken = address(0x00);

    // MATIC token as rewards
    address internal constant MATIC =
        address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

    // Extra reward token price feed
    address internal constant _rewardTokenPriceFeed =
        address(0xAB594600376Ec9fD91F8e885dADF0CE036862dE0);

    // Quickswap (Uniswap V2 fork) router to liquidate MATIC rewards to underlying
    address internal constant _quickswapRouter =
        address(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);

    constructor(address _fund)
        public
        CurveSingleAssetLendingStrategyBase(
            _fund,
            _crvPool,
            _crvPoolToken,
            _crvPoolGauge,
            _crvPoolGaugeType,
            _CRVToken,
            MATIC,
            _rewardTokenPriceFeed,
            _quickswapRouter,
            MATIC,
            true, // AUSD is a wrapped pool
            true // we are depositing underlying coin (not aToken)
        )
    // solhint-disable-next-line no-empty-blocks
    {

    }
}
