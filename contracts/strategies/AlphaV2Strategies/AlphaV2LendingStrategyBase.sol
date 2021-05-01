// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/Math.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/SafeMath.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/IERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/utils/Address.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/SafeERC20.sol";
import "../../../interfaces/strategies/AlphaV2Strategies/IAlphaV2.sol";
import "../../../interfaces/strategies/AlphaV2Strategies/ICErc20.sol";
import "../../../interfaces/uniswap/IUniswapV2Router02.sol";
import "../../../interfaces/IFund.sol";
import "../../../interfaces/IStrategy.sol";
import "../../../interfaces/IGovernable.sol";

/**
 * This strategy takes an asset (DAI, USDC), lends to AlphaV2 Lending Box.
 */
abstract contract AlphaV2LendingStrategyBase is IStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public immutable override underlying;
    address public immutable override fund;
    address public immutable override creator;

    // the alphasafebox corresponding to the underlying asset
    address public immutable aBox;

    // the cToken corresponding to the alphasafebox
    address public immutable cToken;

    // Alpha token as rewards
    address public constant rewardToken =
        address(0xa1faa113cbE53436Df28FF0aEe54275c13B40975);

    // Uniswap V2s router to liquidate Alpha rewards to underlying
    address internal constant _uniswapRouter =
        address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    // WETH serves as path to convert rewards to underlying
    address internal constant WETH =
        address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    // these tokens cannot be claimed by the governance
    mapping(address => bool) public canNotSweep;

    bool public investActivated;

    constructor(address _fund, address _aBox) public {
        require(_fund != address(0), "Fund cannot be empty");
        require(_aBox != address(0), "Alpha Safebox cannot be empty");
        fund = _fund;
        address _underlying = IFund(_fund).underlying();
        require(
            _underlying == IAlphaV2(_aBox).uToken(),
            "Underlying do not match"
        );
        underlying = _underlying;
        aBox = _aBox;
        cToken = IAlphaV2(_aBox).cToken();
        creator = msg.sender;

        // approve max amount to save on gas costs later
        IERC20(_underlying).safeApprove(_aBox, type(uint256).max);

        // restricted tokens, can not be swept
        canNotSweep[_underlying] = true;
        canNotSweep[_aBox] = true;
        canNotSweep[rewardToken] = true;

        investActivated = true;
    }

    function _governance() internal view returns (address) {
        return IGovernable(fund).governance();
    }

    modifier onlyFundOrGovernance() {
        require(
            msg.sender == fund || msg.sender == _governance(),
            "The sender has to be the governance or fund"
        );
        _;
    }

    /**
     *  TODO
     */
    function depositArbCheck() public view override returns (bool) {
        return true;
    }

    /**
     * Allows Governance to withdraw partial shares to reduce slippage incurred
     *  and facilitate migration / withdrawal / strategy switch
     */
    function withdrawPartialShares(uint256 shares)
        external
        onlyFundOrGovernance
    {
        IAlphaV2(aBox).withdraw(shares);
    }

    function setInvestActivated(bool _investActivated)
        external
        onlyFundOrGovernance
    {
        investActivated = _investActivated;
    }

    /**
     * Withdraws an underlying asset from the strategy to the fund in the specified amount.
     * It tries to withdraw from the strategy contract if this has enough balance.
     * Otherwise, we withdraw shares from the Alpha V2 Lending Box. Transfer the required underlying amount to fund,
     * and reinvest the rest. We can make it better by calculating the correct amount and withdrawing only that much.
     */
    function withdrawToFund(uint256 underlyingAmount)
        external
        override
        onlyFundOrGovernance
    {
        uint256 underlyingBalanceBefore =
            IERC20(underlying).balanceOf(address(this));

        if (underlyingBalanceBefore >= underlyingAmount) {
            IERC20(underlying).safeTransfer(fund, underlyingAmount);
            return;
        }

        uint256 shares =
            _shareValueFromUnderlying(
                underlyingAmount.sub(underlyingBalanceBefore)
            );
        uint256 totalShares = IAlphaV2(aBox).balanceOf(address(this));

        if (shares > totalShares) {
            //can't withdraw more than we have
            shares = totalShares;
        }

        IAlphaV2(aBox).withdraw(shares);

        // we can transfer the asset to the fund
        uint256 underlyingBalance = IERC20(underlying).balanceOf(address(this));
        if (underlyingBalance > 0) {
            IERC20(underlying).safeTransfer(
                fund,
                Math.min(underlyingAmount, underlyingBalance)
            );
        }
    }

    /**
     * Withdraws all assets from the Alpha V2 Lending Box and transfers to Fund.
     */
    function withdrawAllToFund() external override onlyFundOrGovernance {
        uint256 shares = IAlphaV2(aBox).balanceOf(address(this));
        IAlphaV2(aBox).withdraw(shares);
        uint256 underlyingBalance = IERC20(underlying).balanceOf(address(this));
        if (underlyingBalance > 0) {
            IERC20(underlying).safeTransfer(fund, underlyingBalance);
        }
    }

    /**
     * Invests all underlying assets into our Alpha V2 Lending Box.
     */
    function _investAllUnderlying() internal {
        if (!investActivated) {
            return;
        }

        uint256 underlyingBalance = IERC20(underlying).balanceOf(address(this));
        if (underlyingBalance > 0) {
            // deposits the entire balance to Alpha V2 Lending Box
            IAlphaV2(aBox).deposit(underlyingBalance);
        }
    }

    /**
     * The hard work only invests all underlying assets
     */
    function doHardWork() external override onlyFundOrGovernance {
        _investAllUnderlying();
    }

    // no tokens apart from underlying should be sent to this contract. Any tokens that are sent here by mistake are recoverable by governance
    function sweep(address _token, address _sweepTo) external {
        require(_governance() == msg.sender, "Not governance");
        require(!canNotSweep[_token], "Token is restricted");
        IERC20(_token).safeTransfer(
            _sweepTo,
            IERC20(_token).balanceOf(address(this))
        );
    }

    function _getPath(address _from, address _to)
        internal
        pure
        returns (address[] memory)
    {
        address[] memory path;
        if (_from == WETH || _to == WETH) {
            path = new address[](2);
            path[0] = _from;
            path[1] = _to;
        } else {
            path = new address[](3);
            path[0] = _from;
            path[1] = WETH;
            path[2] = _to;
        }
        return path;
    }

    function _liquidateRewardsAndReinvest(uint256 minUnderlyingExpected)
        internal
    {
        uint256 rewardAmount = IERC20(rewardToken).balanceOf(address(this));
        if (rewardAmount != 0) {
            IUniswapV2Router02 uniswapRouter =
                IUniswapV2Router02(_uniswapRouter);
            address[] memory path = _getPath(rewardToken, underlying);
            uint256 underlyingAmountOut =
                uniswapRouter.getAmountsOut(rewardAmount, path)[
                    path.length - 1
                ];
            if (underlyingAmountOut != 0) {
                IERC20(rewardToken).safeApprove(_uniswapRouter, rewardAmount);
                uniswapRouter.swapExactTokensForTokens(
                    rewardAmount,
                    minUnderlyingExpected,
                    path,
                    address(this),
                    now + 30
                );
                _investAllUnderlying();
            }
        }
    }

    /**
     * This liquidates all the reward token in this strategy.
     * This doesn't claim the rewards, they need to be claimed externally.
     */
    function liquidateRewardsAndReinvest(uint256 minUnderlyingExpected)
        external
        onlyFundOrGovernance
    {
        _liquidateRewardsAndReinvest(minUnderlyingExpected);
    }

    /**
     * Returns the underlying invested balance. This is the underlying amount based on yield bearing token balance,
     * plus the current balance of the underlying asset.
     */
    function investedUnderlyingBalance()
        external
        view
        override
        returns (uint256)
    {
        uint256 shares = IERC20(aBox).balanceOf(address(this));
        uint256 exchangeRate = ICErc20(cToken).exchangeRateStored();
        uint256 precision = 10**18;
        uint256 underlyingBalanceinABox =
            shares.mul(exchangeRate).div(precision);
        return
            underlyingBalanceinABox.add(
                IERC20(underlying).balanceOf(address(this))
            );
    }

    /**
     * Returns the value of the underlying token in aBox ibToken
     */
    function _shareValueFromUnderlying(uint256 underlyingAmount)
        internal
        view
        returns (uint256)
    {
        return
            underlyingAmount.mul(10**18).div(
                ICErc20(cToken).exchangeRateStored()
            );
    }
}
