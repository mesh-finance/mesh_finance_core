// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface WhitePaperInterestRateModel {
    function getSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactorMantissa
    ) external view returns (uint256);
}
