// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

/**
 * @title Lending strategy for USDC for DyDx
 * @author Mesh Finance
 * @notice Assigns the market id for the USDC pool for DyDx strategy
 */

import "./DyDxLendingStrategyBase.sol";

contract DyDxLendingStrategyMainnetUSDC is DyDxLendingStrategyBase {
    string public constant override name = "DyDxLendingStrategyMainnetUSDC";
    string public constant override version = "V1";

    uint256 internal constant _marketId = 2; // market id 2 represents USDC in DyDx lending pool

    /* solhint-disable no-empty-blocks */
    /// @notice Deploys the DyDx Lending strategy for USDC using the DyDxLendingStrategyBase
    /// @param _fund is the address of the Mesh fund for which we are deploying this strategy.
    constructor(address _fund)
        public
        DyDxLendingStrategyBase(_fund, _marketId)
    {}
    /* solhint-enable no-empty-blocks */
}
