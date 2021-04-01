// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./AlphaV2LendingStrategyBase.sol";

/**
 * Adds the mainnet addresses to the AlphaV2LendingStrategyBase
 */
contract AlphaV2LendingStrategyMainnet is AlphaV2LendingStrategyBase {
    // token addresses
    address public constant dai =
        address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address public constant ibdaiv2 =
        address(0xee8389d235E092b2945fE363e97CDBeD121A0439);
    address public constant usdc =
        address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address public constant ibusdcv2 =
        address(0x08bd64BFC832F1C2B3e07e634934453bA7Fa2db2);

    // pre-defined constant mapping: underlying -> aBox
    mapping(address => address) public aBoxes;

    constructor(address _fund)
        public
        AlphaV2LendingStrategyBase(_fund, address(0), 0)
    {
        aBoxes[dai] = ibdaiv2;
        aBoxes[usdc] = ibusdcv2;
        aBox = aBoxes[underlying];
        require(
            aBox != address(0),
            "underlying not supported: aBox is not defined"
        );
        if (underlying == dai) {
            tokenIndex = TokenIndex.DAI;
        } else if (underlying == usdc) {
            tokenIndex = TokenIndex.USDC;
        } else {
            revert("Asset not supported");
        }
    }
}
