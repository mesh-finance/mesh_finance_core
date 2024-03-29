// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IUpgradeSource {
    function shouldUpgrade() external view returns (bool, address);
}
