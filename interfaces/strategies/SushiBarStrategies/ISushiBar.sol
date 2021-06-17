// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface ISushiBar {
    // ERC20 part
    function balanceOf(address) external view returns (uint256);

    function decimals() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function enter(uint256 amount) external;
    function leave(uint256 share) external;
   

    // VaultV2 user interface
    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;
}
