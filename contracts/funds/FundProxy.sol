// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "../../interfaces/IUpgradeSource.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/proxy/UpgradeableProxy.sol";

contract FundProxy is UpgradeableProxy {
    bytes internal empty;

    constructor(address _implementation)
        public
        UpgradeableProxy(_implementation, empty)
    // solhint-disable-next-line no-empty-blocks
    {

    }

    /**
     * The main logic. If the timer has elapsed and there is a schedule upgrade,
     * the governance can upgrade the vault
     */
    function upgrade(address newImplementation) external {
        // oldImplementation is unused for now
        // solhint-disable-next-line no-unused-vars
        (bool should, address oldImplementation) =
            IUpgradeSource(address(this)).shouldUpgrade();
        require(should, "Upgrade not scheduled");
        _upgradeTo(newImplementation);

        // the finalization needs to be executed on itself to update the storage of this proxy
        // it also needs to be invoked by the governance, not by address(this), so delegatecall is needed

        // result is unused for now
        // solhint-disable-next-line no-unused-vars
        (bool success, bytes memory result) =
            // solhint-disable-next-line avoid-low-level-calls
            address(this).delegatecall(
                abi.encodeWithSignature("finalizeUpgrade()")
            );

        require(success, "Issue when finalizing the upgrade");
    }

    function implementation() external view returns (address) {
        return _implementation();
    }
}
