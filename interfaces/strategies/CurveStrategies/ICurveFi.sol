// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface ICurveFi {
    function coins(uint256) external view returns (address);

    function underlying_coins(uint256) external view returns (address);

    function get_virtual_price() external view returns (uint256);

    function calc_token_amount(uint256[3] calldata amounts, bool is_deposit)
        external
        view
        returns (uint256);

    function add_liquidity(
        // CRV 3 pool
        uint256[3] calldata amounts,
        uint256 min_mint_amount
    ) external;

    function add_liquidity(
        // wrapped aave pool
        uint256[3] calldata amounts,
        uint256 min_mint_amount,
        bool use_underlying
    ) external;

    function calc_withdraw_one_coin(uint256 _amount, int128 i)
        external
        view
        returns (uint256);

    function remove_liquidity_one_coin(
        uint256 _token_amount,
        int128 i,
        uint256 min_amount
    ) external;

    function remove_liquidity_one_coin(
        uint256 _token_amount,
        int128 i,
        uint256 min_amount,
        bool use_underlying
    ) external;
}
