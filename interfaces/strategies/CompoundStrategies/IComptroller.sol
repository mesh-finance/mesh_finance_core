// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IComptroller {
    function claimComp(address holder, address[] memory) external;

    function compAccrued(address holder) external view returns (uint256);

    function compSpeeds(address cToken) external view returns (uint256);
}
