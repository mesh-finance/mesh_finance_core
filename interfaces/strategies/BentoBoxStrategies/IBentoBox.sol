// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IBentoBox {
    // ERC20 part
    function balanceOf(address,address) external view returns (uint256);


    function toShare() external view returns (uint256);

    function toAmount() external view returns (uint256);

    function registerProtocol() external;

    function setMasterContractApproval (
        address user,
        address masterContract,
        bool approved,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external; 

    // VaultV2 user interface
    function deposit(address token, address from, address to, uint256 amount, uint256 share) external;

    function withdraw(uint256 amount) external;
}
