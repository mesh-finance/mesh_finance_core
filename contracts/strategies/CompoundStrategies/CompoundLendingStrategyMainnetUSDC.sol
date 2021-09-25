// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./CompoundLendingStrategyBase.sol";

/**
 * Adds the mainnet usdc addresses to the CompoundLendingStrategyBase
 */
contract CompoundLendingStrategyMainnetUSDC is CompoundLendingStrategyBase {
    string public constant override name = "CompoundLendingStrategyMainnetUSDC";
    string public constant override version = "V1";

    address internal constant _cToken =
        address(0x39AA39c021dfbaE8faC545936693aC917d5E7563);

    // COMP token as reward
    address internal constant _rewardToken =
        address(0xc00e94Cb662C3520282E6f5717214004A7f26888);

    // Comptroller to claim reward
    address internal constant _comptroller =
        address(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

    // Reward token price feed
    address internal constant rewardTokenPriceFeed_ =
        address(0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5);

    // Uniswap V2s router to liquidate COMP rewards to underlying
    address internal constant _uniswapRouter =
        address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    // WETH serves as path to convert rewards to underlying
    address internal constant WETH =
        address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    constructor(address _fund)
        public
        CompoundLendingStrategyBase(
            _fund,
            _cToken,
            _rewardToken,
            _comptroller,
            rewardTokenPriceFeed_,
            _uniswapRouter,
            WETH
        )
    // solhint-disable-next-line no-empty-blocks
    {

    }
}
