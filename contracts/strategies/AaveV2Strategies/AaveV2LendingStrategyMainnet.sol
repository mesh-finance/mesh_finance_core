// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./AaveV2LendingStrategyBase.sol";

/**
 * Adds the mainnet addresses to the AaveV2LendingStrategyBase
 */
contract AaveV2LendingStrategyMainnet is AaveV2LendingStrategyBase {
    string public constant override name = "AaveV2LendingStrategyMainnet";
    string public constant override version = "V1";

    // Address provider for AAVE
    address internal constant _aaveAddressProvider =
        address(0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5);

    // Incentive Controller for rewards
    address internal constant _incentivesController =
        address(0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5);

    // stkAave token as rewards
    address internal constant _rewardToken =
        address(0x4da27a545c0c5B758a6BA100e3a049001de870f5);

    // Aave token as rewards after unstaking
    address internal constant _unstakedRewardToken =
        address(0x4da27a545c0c5B758a6BA100e3a049001de870f5);

    // Uniswap V2s router to liquidate stkAave rewards to underlying
    address internal constant _uniswapRouter =
        address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    // WETH serves as path to convert rewards to underlying
    address internal constant WETH =
        address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    constructor(address _fund)
        public
        AaveV2LendingStrategyBase(
            _fund,
            _aaveAddressProvider,
            _incentivesController,
            _rewardToken,
            _unstakedRewardToken,
            _uniswapRouter,
            WETH
        )
    // solhint-disable-next-line no-empty-blocks
    {

    }

    // TODO
    // ClaimStakingRewards
    // UnstakeRewards (start cooldown)
    // Redeem Rewards
    // https://docs.aave.com/developers/protocol-governance/staking-aave#integrating-staking
}
