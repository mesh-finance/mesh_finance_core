// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/IERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/presets/ERC20PresetMinterPauser.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/utils/Address.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/Math.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/SafeMath.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/SafeERC20.sol";
import "../../../interfaces/IStrategy.sol";
import "../../../interfaces/IGovernable.sol";
import "../../../interfaces/uniswap/IUniswapV2Router02";
import "../../../interfaces/uniswap/IUniswapV2Pair";
import "../../../interfaces/uniswap/IStakingRewards";
import "../../oracles/SimplePriceOracle";

contract QuickswapStrategy is IStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // solhint-disable-next-line const-name-snakecase
    string public constant override name = "QuickswapStrategyUSDC";
    // solhint-disable-next-line const-name-snakecase
    string public constant override version = "V1";

    uint256 internal constant MAX_BPS = 10000; // 100% in basis points

    address public override fund;
    address public override creator;

    uint256 internal accountedBalance;

    // These tokens cannot be claimed by the controller
    mapping(address => bool) public unsalvagableTokens;

    // Quickswap (Uniswap V2 fork) router to liquidate MATIC rewards to USDC
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

    constructor(address _fund) public {
        require(_fund != address(0), "Fund cannot be empty");

        fund = _fund;
        creator = msg.sender;
        QUICK_USDC_priceOracle = SimplePriceOracle(quickswapFactory, QUICK, USDC);
        rUSD_USDC_priceOracle = SimplePriceOracle(quickswapFactory, rUSD, USDC);
        _updateOracles();
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
        _updateOracles();
        uint rUSD_invested = rUSD_USDC_priceOracle.consult(rUSD, rUSD_liquidityAdded);
        return IERC20(USDC).balanceOf(address(this)).add(USDC_liquidityAdded).add(rUSD_invested);
    }

    /*
     * Invests all tokens that were accumulated so far
     */
    function investAllUnderlying() public {

        //We know that underlying is USDC in this case so we are
        uint USDCBalance = IERC20(USDC).balanceOf(address(this));
        
        require(USDCBalance > 0, "No funds available to invest");

        //Invest 90% of input capital
        uint minAmountToInvest = USDCBalance.mul(90).div(100);
        uint amountToRUSD = minAmountToInvest.div(2);

        //Swap USDC for rUSD
        _swapToken(USDC, rUSD, amountToRUSD, rUSD_USDC_priceOracle);

        //Add liquidity for USDC/rUSD pool
        uint rUSDBalance = IERC20(rUSD).balanceOf(address(this));
        _grantApproval(rUSD, _quickswapRouter, rUSDBalance);
        IUniswapV2Router02(_quickswapRouter).addLiquidity(USDC, rUSD, amountToRUSD, rUSDBalance, amountToRUSD.mul(95).div(100), rUSDBalance.mul(95).div(100), address(this), 20 minutes);

        //Calculate how much liquidity has actually been added
        USDC_liquidityAdded = USDCBalance - IERC20(USDC).balanceOf(address(this));
        rUSD_liquidityAdded = rUSDBalance - IERC20(rUSD).balanceOf(address(this));

        //Stake available LP Tokens
        uint rUSD_USDC_LPTokenBalance = IUniswapV2Pair(rUSD_USDC_LPToken).balanceOf(address(this));
        _grantApproval(rUSD_USDC_LPToken, quickswapReward_rUSD_USDC_Pool, rUSD_USDC_LPTokenBalance);
        IStakingRewards(quickswapReward_rUSD_USDC_Pool).stake(rUSD_USDC_LPTokenBalance);

        accountedBalance = IERC20(USDC).balanceOf(address(this));
    }

    /*
     * Cashes everything out and withdraws to the fund
     */
    function withdrawAllToFund() external override onlyFundOrGovernance {
        
        // Withdraw LP Tokens and claim QUICK and convert to USDC
        _claimQUICKRewardsToUSDC();

        // Exit liquidity pool for rUSD and USDC
        _withdrawLiquidtyToUSDC();
        
        
        IERC20(USDC).safeTransfer(
            fund,
            IERC20(USDC).balanceOf(address(this))
        );
        accountedBalance = IERC20(USDC).balanceOf(address(this));
    }

    /*
     * Cashes some amount out and withdraws to the fund
     */
    function withdrawToFund(uint256 amount)
        external
        override
        onlyFundOrGovernance
    {
        require(amount < investedUnderlyingBalance(), "Amount higher than initial capital requested");

        uint256 USDCBalance = IERC20(USDC).balanceOf(address(this));
        if(USDCBalance > amount){
            IERC20(USDC).safeTransfer(fund, amountTowithdraw);
        } else {
            // Calculate amount of QUICK earned
            uint QUICK_earned = IStakingRewards(quickswapReward_rUSD_USDC_Pool).earned(address(this));
            uint USDC_valueOf_QUICK_earned = QUICK_USDC_priceOracle.consult(QUICK, QUICK_earned);

            if(USDCBalance + USDC_valueOf_QUICK_earned < amount){
                // If this is not enough, we exit our positions
                _withdrawLiquidtyToUSDC();
            }
            // Claim QUICK and sell for USDC
            _claimQUICKRewardsToUSDC();
        }


        IERC20(USDC).safeTransfer(
            fund,
            amount
        );

        accountedBalance = IERC20(USDC).balanceOf(address(this));
        
        // Reinvest remaining tokens
        if(accountedBalance > 0){
            investAllUnderlying();
        }

    }

    /*
     * Honest harvesting. It's not much, but it pays off
     */
    // solhint-disable-next-line no-empty-blocks
    function doHardWork() external override onlyFundOrGovernance {
        investAllUnderlying();   // call this externally for testing as profit generation should be after invesment
    }

    function _claimQUICKRewardsToUSDC() internal {
        IStakingRewards(quickswapReward_rUSD_USDC_Pool).getReward();
        uint QUICK_balance = IERC20(QUICK).balanceOf(address(this));
        _swapToken(QUICK, USDC, QUICK_balance, QUICK_USDC_priceOracle);        
    }

    function _withdrawLiquidtyToUSDC()internal {

        IStakingRewards(quickswapReward_rUSD_USDC_Pool).exit();
        
        //Available LP Tokens
        uint rUSD_USDC_LPTokenBalance = IUniswapV2Pair(rUSD_USDC_LPToken).balanceOf(address(this));
        
        // Taking this into account because we want to keep track of liquidity provision
        uint rUSDBalance = IERC20(rUSD).balanceOf(address(this)); //Should be 0 technically
        uint USDCBalance = IERC20(USDC).balanceOf(address(this));

        IUniswapV2Router02(_quickswapRouter).removeLiquidity(USDC, rUSD, rUSD_USDC_LPTokenBalance, USDC_liquidityAdded.mul(97).div(100), rUSD_liquidityAdded.mul(97).div(100), address(this), 20 minutes);
        
        //Update liquidity added variables        
        USDC_liquidityAdded = USDC_liquidityAdded.sub(IERC20(USDC).balanceOf(address(this)).sub(USDCBalance));
        rUSD_liquidityAdded = rUSD_liquidityAdded.sub(IERC20(rUSD).balanceOf(address(this)).sub(rUSDBalance));

        //Swap rUSD for USDC
        _swapToken(rUSD, USDC, IERC20(rUSD).balanceOf(address(this)), rUSD_USDC_priceOracle);

    }
    function _swapToken(address inputToken, address outputToken, uint inputAmount, SimplePriceOracle priceOracle) internal {
        require(IERC20(inputToken).balanceOf(address) >= inputAmount, "Insufficient balance for swap");
        _grantApproval(inputToken, _quickswapRouter, inputAmount);
        //Update Oracles
        _updateOracles();
        //Calculate minOutputAmount 
        uint minOutputAmount = priceOracle.consult(inputToken, inputAmount);
        //Execute swap
        IUniswapV2Router02(_quickswapRouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(inputAmount, minOutputAmount, [inputToken, outputToken], address(this), 20 minutes);

    }
    // Keeping this public because anyone is more than welcome to execute this for us (Oracle Maintainance)
    function _updateOracles() public {
        rUSD_USDC_priceOracle.update();
        QUICK_USDC_priceOracle.update();
    }

    function _grantApproval(address token, address receiver,uint tokenAmount) internal {
        if(IERC20(token).allowance(address(this),reciever) < tokenAmount){
            IERC20(token).approve(reciever, tokenAmount.sub(IERC20(token).allowance(address(this), reciever)));
        }
    }
    // no tokens apart from USDC should be sent to this contract. Any tokens that are sent here by mistake are recoverable by governance
    function sweep(address _token, address _sweepTo) external {
        require(governance() == msg.sender, "Not governance");
        require(_token != USDC, "can not sweep USDC");
        IERC20(_token).safeTransfer(
            _sweepTo,
            IERC20(_token).balanceOf(address(this))
        );
    }
}
