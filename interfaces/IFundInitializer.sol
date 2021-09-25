// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IFundInitializer {
    function initializeFund(
        address _governance,
        address _underlying,
        string memory _name,
        string memory _symbol
    ) external;
}
