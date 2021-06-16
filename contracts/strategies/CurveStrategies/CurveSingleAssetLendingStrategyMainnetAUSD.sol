// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./CurveSingleAssetLendingStrategyBase.sol";

/**
 * Adds the mainnet addresses to the CurveSingleAssetLendingStrategyBase
 */
contract CurveSingleAssetLendingStrategyMainnetAUSD is
    CurveSingleAssetLendingStrategyBase
{
    string public constant override name =
        "CurveSingleAssetLendingStrategyMainnetAUSD";
    string public constant override version = "V1";

    // Required Curve Pool (Aave USD)
    address internal constant _crvPool =
        address(0xDeBF20617708857ebe4F679508E7b7863a8A8EeE);

    // Corresponding curve pool token (a3crv)
    address internal constant _crvPoolToken =
        address(0xFd2a8fA60Abd58Efe3EeE34dd494cD491dC14900);

    // Gauge for rewards
    address internal constant _crvPoolGauge =
        address(0xd662908ADA2Ea1916B3318327A97eB18aD588b5d);

    // Gauge type. Rewards: {1: Only CRV, 2: CRV + Reward, 3: Only Reward}
    uint8 internal constant _crvPoolGaugeType = 2;

    // CRV token as rewards
    address internal constant _CRVToken =
        address(0xD533a949740bb3306d119CC777fa900bA034cd52);

    // Extra reward token (stkAAVE in this case)
    address internal constant _rewardToken =
        address(0x4da27a545c0c5B758a6BA100e3a049001de870f5);

    // Extra reward token price feed
    address internal constant _rewardTokenPriceFeed =
        address(0x547a514d5e3769680Ce22B2361c10Ea13619e8a9);

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
            true, // AUSD is a wrapped pool
            true // we are depositing underlying coin (not aToken)
        )
    // solhint-disable-next-line no-empty-blocks
    {

    }

    // TODO for reward tokens (stkAAVE)
    // ClaimStakingRewards
    // UnstakeRewards (start cooldown)
    // Redeem Rewards
    // https://docs.aave.com/developers/protocol-governance/staking-aave#integrating-staking
}
