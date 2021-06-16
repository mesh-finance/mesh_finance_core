// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/utils/Address.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/SafeERC20.sol";
import "../../../interfaces/uniswap/IUniswapV2Router02.sol";

library SwapTokensLibrary {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    function _getPath(
        address _from,
        address _to,
        address _baseCurrency
    ) internal pure returns (address[] memory) {
        address[] memory path;
        if (_from == _baseCurrency || _to == _baseCurrency) {
            path = new address[](2);
            path[0] = _from;
            path[1] = _to;
        } else {
            path = new address[](3);
            path[0] = _from;
            path[1] = _baseCurrency;
            path[2] = _to;
        }
        return path;
    }

    function _liquidateRewards(
        address rewardToken,
        address underlying,
        address _dEXRouter,
        address _baseCurrency,
        uint256 minUnderlyingExpected
    ) internal {
        uint256 rewardAmount = IERC20(rewardToken).balanceOf(address(this));
        if (rewardAmount != 0) {
            IUniswapV2Router02 dEXRouter = IUniswapV2Router02(_dEXRouter);
            address[] memory path =
                _getPath(rewardToken, underlying, _baseCurrency);
            uint256 underlyingAmountOut =
                dEXRouter.getAmountsOut(rewardAmount, path)[path.length - 1];
            if (underlyingAmountOut != 0) {
                IERC20(rewardToken).safeApprove(_dEXRouter, rewardAmount);
                dEXRouter.swapExactTokensForTokens(
                    rewardAmount,
                    minUnderlyingExpected,
                    path,
                    address(this),
                    // solhint-disable-next-line not-rely-on-time
                    now + 30
                );
            }
        }
    }
}
