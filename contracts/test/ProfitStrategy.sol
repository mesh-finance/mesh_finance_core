// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/IERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/presets/ERC20PresetMinterPauser.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/utils/Address.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/Math.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/SafeMath.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/SafeERC20.sol";
import "../../interfaces/IStrategy.sol";
import "../../interfaces/IFund.sol";
import "../../interfaces/IGovernable.sol";
import "../../interfaces/uniswap/IUniswapV2Router02";
import "../../interfaces/uniswap/IUniswapV2Pair";
import "../../interfaces/uniswap/IStakingRewards";

import "../oracles/SimplePriceOracle";
contract ProfitStrategy is IStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // solhint-disable-next-line const-name-snakecase
    string public constant override name = "ProfitStrategy";
    // solhint-disable-next-line const-name-snakecase
    string public constant override version = "V1";

    uint256 internal constant MAX_BPS = 10000; // 100% in basis points

    address public override underlying;
    address public override fund;
    address public override creator;

    uint256 internal accountedBalance;
    uint256 internal profitPerc;

    // These tokens cannot be claimed by the controller
    mapping(address => bool) public unsalvagableTokens;

    // Quickswap (Uniswap V2 fork) router to liquidate MATIC rewards to underlying
    address internal constant _quickswapRouter =
        address(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);

    address constant rUSD = 0xfc40a4f89b410a1b855b5e205064a38fc29f5eb5;
    address constant USDC = 0x2791bca1f2de4661ed88a30c99a7a9449aa84174;
    address constant QUICK = 0x831753dd7087cac61ab5644b308642cc1c33dc13;
    address constant quickswapReward_rUSD_USDC_Pool = 0x5C1186F784A4fEFd53Dc40c492b02dEEd97E7944;
    address constant quickswapFactory = 0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32;
    address constant rUSD_USDC_LPToken = 0x5ef8747d1dc4839e92283794a10d448357973ac0;
    SimplePriceOracle QUICK_USDC_priceOracle;
    SimplePriceOracle rUSD_USDC_priceOracle;

    uint USDC_liquidityAdded = 0;
    uint rUSD_liquidityAdded = 0;

    constructor(address _fund, uint256 _profitPerc) public {
        require(_fund != address(0), "Fund cannot be empty");
        // We assume that this contract is a minter on underlying
        fund = _fund;
        underlying = IFund(fund).underlying();
        profitPerc = _profitPerc;
        creator = msg.sender;

        QUICK_USDC_priceOracle = SimplePriceOracle(quickswapFactory, QUICK, USDC);
        rUSD_USDC_priceOracle = SimplePriceOracle(quickswapFactory, rUSD, USDC);
    }

    function governance() internal returns (address) {
        return IGovernable(fund).governance();
    }

    function depositArbCheck() public view override returns (bool) {
        return true;
    }

    modifier onlyFundOrGovernance() {
        require(
            msg.sender == fund || msg.sender == governance(),
            "The sender has to be the governance or fund"
        );
        _;
    }

    /*
     * Returns the total invested amount.
     */
    function investedUnderlyingBalance()
        public
        view
        override
        returns (uint256)
    {
        // for real strategies, need to calculate the invested balance
        return IERC20(underlying).balanceOf(address(this));
    }

    /*
     * Invests all tokens that were accumulated so far
     */
    function investAllUnderlying() public {
        uint256 contribution =
            IERC20(underlying).balanceOf(address(this)).sub(accountedBalance);
        // add 10% to this strategy
        // We assume that this contract is a minter on underlying
        // uint rUSDBalance = IERC20(rUSD).balanceOf(address(this))
        // underlyingToken is USDC
        uint underlyingBalance = IERC20(underlying).balanceOf(address(this));
        
        uint minAmountToInvest = underlyingBalance.mul(90).div(100);
        uint amountToRUSD = minAmountToInvest.div(2);

        uint minOutputAmount = rUSD_USDC_priceOracle.consult(USDC, amountToRUSD);

        // Swap
        IUniswapV2Router02(_quickswapRouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(amountToRUSD, minOutputAmount, [USDC, rUSD], address(this), 20 minutes);

        uint rUSDBalance = IERC20(rUSD).balanceOf(address(this));
        IUniswapV2Router02(_quickswapRouter).addLiquidity(USDC, rUSD, amountToRUSD, rUSDBalance, amountToRUSD.mul(95).div(100), rUSDBalance.mul(95).div(100), address(this), 20 minutes);

        //Calculate how much liquidity has actually been added
        USDC_liquidityAdded = underlyingBalance - IERC20(USDC).balanceOf(address(this));
        rUSD_liquidityAdded = rUSDBalance - IERC20(rUSD).balanceOf(address(this));

        //Available LP Tokens
        uint rUSD_USDC_LPTokenBalance = IUniswapV2Pair(rUSD_USDC_LPToken).balanceOf(address(this));

        IStakingRewards(quickswapReward_rUSD_USDC_Pool).stake(rUSD_USDC_LPToken);

        ERC20PresetMinterPauser(underlying).mint(
            address(this),
            contribution.mul(profitPerc).div(MAX_BPS)
        );
        accountedBalance = IERC20(underlying).balanceOf(address(this));
    }

    /*
     * Cashes everything out and withdraws to the fund
     */
    function withdrawAllToFund() external override onlyFundOrGovernance {
        
        // Withdraw LP Tokens and claim QUICK
        IStakingRewards(quickswapReward_rUSD_USDC_Pool).exit();

        // Sell farmed QUICK rewards
        uint quickTokenBalance = IERC20(QUICK).balanceOf(address(this));

        uint minOutputAmount = QUICK_USDC_priceOracle.consult(QUICK, quickTokenBalance);

        IUniswapV2Router02(_quickswapRouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(quickTokenBalance, minOutputAmount, [QUICK, USDC], address(this), 20 minutes);

        // Exit liquidity pool for rUSD and USDC

        //Available LP Tokens
        uint rUSD_USDC_LPTokenBalance = IUniswapV2Pair(rUSD_USDC_LPToken).balanceOf(address(this));
        uint rUSDBalance = IERC20(rUSD).balanceOf(address(this));
        uint USDCBalance = IERC20(USDC).balanceOf(address(this));

        IUniswapV2Router02(_quickswapRouter).removeLiquidity(USDC, rUSD, rUSD_USDC_LPTokenBalance, USDC_liquidityAdded.mul(97).div(100), rUSD_liquidityAdded.mul(97).div(100), address(this), 20 minutes);
        
        //Update liquidity added variables        
        USDC_liquidityAdded = USDC_liquidityAdded.sub(IERC20(USDC).balanceOf(address(this)).sub(USDCBalance));
        rUSD_liquidityAdded = rUSD_liquidityAdded/sub(IERC20(rUSD).balanceOf(address(this)).sub(rUSDBalance));

        // Sell rUSD for USDC

        rUSDBalance = IERC20(rUSD).balanceOf(address(this));
        uint minOutputAmount = rUSD_USDC_priceOracle.consult(rUSD, rUSDBalance);

        // Swap
        IUniswapV2Router02(_quickswapRouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(rUSDC, minOutputAmount, [rUSD, USDC], address(this), 20 minutes);

        
        
        IERC20(underlying).safeTransfer(
            fund,
            IERC20(underlying).balanceOf(address(this))
        );
        accountedBalance = IERC20(underlying).balanceOf(address(this));
    }

    /*
     * Cashes some amount out and withdraws to the fund
     */
    function withdrawToFund(uint256 amount)
        external
        override
        onlyFundOrGovernance
    {
        uint256 underlyingBalance = IERC20(underlying).balanceOf(address(this));
        uint256 amountTowithdraw = Math.min(underlyingBalance, amount);
        IERC20(underlying).safeTransfer(fund, amountTowithdraw);
        accountedBalance = IERC20(underlying).balanceOf(address(this));
    }

    /*
     * Honest harvesting. It's not much, but it pays off
     */
    // solhint-disable-next-line no-empty-blocks
    function doHardWork() external override onlyFundOrGovernance {
        investAllUnderlying();   // call this externally for testing as profit geeneration should be after invesment
    }

    // no tokens apart from underlying should be sent to this contract. Any tokens that are sent here by mistake are recoverable by governance
    function sweep(address _token, address _sweepTo) external {
        require(governance() == msg.sender, "Not governance");
        require(_token != underlying, "can not sweep underlying");
        IERC20(_token).safeTransfer(
            _sweepTo,
            IERC20(_token).balanceOf(address(this))
        );
    }
}
