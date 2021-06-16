// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/utils/Address.sol";
import "../../../interfaces/chainlink/AggregatorV3Interface.sol";

library PriceFeedLibrary {
    using Address for address;

    function _getDecimals(address priceFeed) internal view returns (uint8) {
        return AggregatorV3Interface(priceFeed).decimals();
    }

    /* solhint-disable no-unused-vars */
    function _getPrice(address priceFeed) internal view returns (int256) {
        (
            uint80 roundID,
            int256 price,
            uint256 startedAt,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = AggregatorV3Interface(priceFeed).latestRoundData();
        return price;
    }
    /* solhint-enable no-unused-vars */
}
