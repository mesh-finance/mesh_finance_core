// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./CurveSingleAssetLendingStrategyBase.sol";

/**
 * Adds the mainnet addresses to the CurveSingleAssetLendingStrategyBase
 */
contract CurveSingleAssetLendingStrategyMainnet3Pool is
    CurveSingleAssetLendingStrategyBase
{
    string public constant override name =
        "CurveSingleAssetLendingStrategyMainnet3Pool";
    string public constant override version = "V1";

    // Required Curve Pool (3 Pool)
    address internal constant _crvPool =
        address(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);

    // Corresponding curve pool token (3Crv)
    address internal constant _crvPoolToken =
        address(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);

    // Gauge for rewards
    address internal constant _crvPoolGauge =
        address(0xbFcF63294aD7105dEa65aA58F8AE5BE2D9d0952A);

    // Gauge type. Rewards: {1: Only CRV, 2: CRV + Reward, 3: Only Reward}
    uint8 internal constant _crvPoolGaugeType = 1;

    // CRV token as rewards
    address internal constant _CRVToken =
        address(0xD533a949740bb3306d119CC777fa900bA034cd52);

    // Extra reward token (none in this case)
    address internal constant _rewardToken = address(0x00);

    // Extra reward token price feed (none in this case)
    address internal constant _rewardTokenPriceFeed = address(0x00);

    // Uniswap V2s router to liquidate stkAave rewards to underlying
    address internal constant _uniswapRouter =
        address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    // WETH serves as path to convert rewards to underlying
    address internal constant WETH =
        address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    constructor(address _fund)
        public
        CurveSingleAssetLendingStrategyBase(
            _fund,
            _crvPool,
            _crvPoolToken,
            _crvPoolGauge,
            _crvPoolGaugeType,
            _CRVToken,
            _rewardToken,
            _rewardTokenPriceFeed,
            _uniswapRouter,
            WETH,
            false, // 3CRV not wrapped pool
            true // doesn't matter since it is not a wrapped pool
        )
    // solhint-disable-next-line no-empty-blocks
    {

    }
}
