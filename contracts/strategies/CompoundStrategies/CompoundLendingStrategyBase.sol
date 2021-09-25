// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/Math.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/SafeMath.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/IERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/utils/Address.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/SafeERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/ERC20.sol";
import "../../../interfaces/strategies/CompoundStrategies/ICToken.sol";
import "../../../interfaces/strategies/CompoundStrategies/WhitePaperInterestRateModel.sol";
import "../../../interfaces/strategies/CompoundStrategies/IComptroller.sol";
import "../../../interfaces/IFund.sol";
import "../../../interfaces/IStrategy.sol";
import "../../../interfaces/IStrategyUnderOptimizer.sol";
import "../../../interfaces/IGovernable.sol";
import "../../utils/SwapTokensLibrary.sol";
import "../../utils/PriceFeedLibrary.sol";

/**
 * @title Lending strategy for Compound
 * @author Mesh Finance
 * @notice This strategy lends asset to compound
 */
abstract contract CompoundLendingStrategyBase is
    IStrategy,
    IStrategyUnderOptimizer
{
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    uint256 internal constant PRECISION = 10**18;

    uint256 internal constant MAX_BPS = 10000;
    uint256 internal constant APR_BASE = 10**6;

    uint256 internal constant BLOCKS_PER_YEAR = 2371428;

    address public immutable override underlying;
    address public immutable override fund;
    address public immutable override creator;

    // the c-token corresponding to the underlying asset
    address public immutable cToken;

    // Reward Token
    address public immutable rewardToken;

    // Comptroller to claim reward tokens
    address public immutable comptroller;

    // Price feed for reward token
    address internal immutable _rewardTokenPriceFeed;

    // DEX router to liquidate rewards to underlying
    address internal immutable _dEXRouter;

    // base currency serves as path to convert rewards to underlying
    address internal immutable _baseCurrency;

    uint256 internal allowedSlippage = 500; // In BPS, can be changed

    // these tokens cannot be claimed by the governance
    mapping(address => bool) public canNotSweep;

    bool public investActivated;

    constructor(
        address _fund,
        address _cToken,
        address _rewardToken,
        address _comptroller,
        address rewardTokenPriceFeed_,
        address dEXRouter_,
        address baseCurrency_
    ) public {
        require(_fund != address(0), "Fund cannot be empty");
        require(_cToken != address(0), "cToken cannot be empty");
        fund = _fund;
        address _underlying = IFund(_fund).underlying();
        require(
            _underlying == ICToken(_cToken).underlying(),
            "Underlying do not match"
        );
        underlying = _underlying;
        cToken = _cToken;
        rewardToken = _rewardToken;
        comptroller = _comptroller;
        _rewardTokenPriceFeed = rewardTokenPriceFeed_;
        _dEXRouter = dEXRouter_;
        _baseCurrency = baseCurrency_;
        creator = msg.sender;

        // restricted tokens, can not be swept
        canNotSweep[_underlying] = true;
        canNotSweep[_cToken] = true;
        canNotSweep[_rewardToken] = true;

        investActivated = true;
    }

    function _governance() internal view returns (address) {
        return IGovernable(fund).governance();
    }

    function _fundManager() internal view returns (address) {
        return IFund(fund).fundManager();
    }

    function _relayer() internal view returns (address) {
        return IFund(fund).relayer();
    }

    modifier onlyFund() {
        require(msg.sender == fund, "The sender has to be the fund");
        _;
    }

    modifier onlyFundOrGovernance() {
        require(
            msg.sender == fund || msg.sender == _governance(),
            "The sender has to be the governance or fund"
        );
        _;
    }

    modifier onlyFundManagerOrGovernance() {
        require(
            msg.sender == _fundManager() || msg.sender == _governance(),
            "The sender has to be the governance or fund manager"
        );
        _;
    }

    modifier onlyFundManagerOrRelayer() {
        require(
            msg.sender == _fundManager() || msg.sender == _relayer(),
            "The sender has to be the relayer or fund manager"
        );
        _;
    }

    /**
     * @notice Allows Governance/Fund manager to withdraw partial shares to reduce slippage incurred
     * and facilitate migration / withdrawal / strategy switch
     * @param shares cTokens to withdraw
     */
    function withdrawPartialShares(uint256 shares)
        external
        onlyFundManagerOrGovernance
    {
        require(shares > 0, "Shares should be greater than 0");
        uint256 redeemResult = ICToken(cToken).redeem(shares);
        require(redeemResult == 0, "Error calling redeem on Compound");
    }

    /**
     * @notice Allows Governance/Fund Manager to stop/start lending assets from this strategy to Compound
     * @dev Used for emergencies
     * @param _investActivated Set investment to True/False
     */
    function setInvestActivated(bool _investActivated)
        external
        onlyFundManagerOrGovernance
    {
        investActivated = _investActivated;
    }

    /**
     * @notice Withdraws an underlying asset from the strategy to the fund in the specified amount.
     * It tries to withdraw from the strategy contract if this has enough balance.
     * Otherwise, we redeem cToken. Transfer the required underlying amount to fund.
     * Reinvest any remaining underlying.
     * @param underlyingAmount Underlying amount to withdraw to fund
     */
    function withdrawToFund(uint256 underlyingAmount)
        external
        override
        onlyFund
    {
        uint256 underlyingBalanceBefore =
            IERC20(underlying).balanceOf(address(this));

        if (underlyingBalanceBefore >= underlyingAmount) {
            IERC20(underlying).safeTransfer(fund, underlyingAmount);
            return;
        }

        uint256 redeemResult =
            ICToken(cToken).redeemUnderlying(
                underlyingAmount.sub(underlyingBalanceBefore)
            );

        require(
            redeemResult == 0,
            "Error calling redeemUnderlying on Compound"
        );

        // we can transfer the asset to the fund
        uint256 underlyingBalance = IERC20(underlying).balanceOf(address(this));
        if (underlyingBalance > 0) {
            if (underlyingAmount < underlyingBalance) {
                IERC20(underlying).safeTransfer(fund, underlyingAmount);
                _investAllUnderlying();
            } else {
                IERC20(underlying).safeTransfer(fund, underlyingBalance);
            }
        }
    }

    /**
     * @notice Withdraws all assets from compound and transfers all underlying to fund.
     */
    function withdrawAllToFund() external override onlyFund {
        uint256 cTokenBalance = ICToken(cToken).balanceOf(address(this));
        uint256 redeemResult = ICToken(cToken).redeem(cTokenBalance);
        require(redeemResult == 0, "Error calling redeem on Compound");
        _claimRewards();
        _liquidateRewards();
        uint256 underlyingBalance = IERC20(underlying).balanceOf(address(this));
        if (underlyingBalance > 0) {
            IERC20(underlying).safeTransfer(fund, underlyingBalance);
        }
    }

    /**
     * @notice Invests all underlying assets into compound.
     */
    function _investAllUnderlying() internal {
        if (!investActivated) {
            return;
        }

        uint256 underlyingBalance = IERC20(underlying).balanceOf(address(this));
        if (underlyingBalance > 0) {
            // approve amount per transaction
            IERC20(underlying).safeApprove(cToken, 0);
            IERC20(underlying).safeApprove(cToken, underlyingBalance);
            // deposits the entire balance to compound
            uint256 mintResult = ICToken(cToken).mint(underlyingBalance);
            require(mintResult == 0, "Error calling mint on Compound");
        }
    }

    /**
     * @notice This claims and liquidates all comp rewards.
     * Then invests all the underlying balance to Compound.
     */
    function doHardWork() external override onlyFund {
        _claimRewards();
        _liquidateRewards();
        _investAllUnderlying();
    }

    /**
     * @notice Returns the underlying invested balance. This is the underlying amount in cToken, plus the current balance of the underlying asset.
     * @return Total balance invested in the strategy
     */
    function investedUnderlyingBalance()
        external
        view
        override
        returns (uint256)
    {
        uint256 cTokenBalance = ICToken(cToken).balanceOf(address(this));
        uint256 exchangeRate = ICToken(cToken).exchangeRateStored();
        uint256 underlyingBalanceinCToken =
            cTokenBalance.mul(exchangeRate).div(PRECISION);
        return
            underlyingBalanceinCToken.add(
                IERC20(underlying).balanceOf(address(this))
            );
    }

    /**
     * Returns the value of the underlying token in cToken
     */
    function _shareValueFromUnderlying(uint256 underlyingAmount)
        internal
        view
        returns (uint256)
    {
        
        uint256 exchangeRate = ICToken(cToken).exchangeRateStored();
        return underlyingAmount.mul(PRECISION).div(exchangeRate);
    }

    
    function _getRewardsBalance() internal view returns (uint256) {
        uint256 rewardsBalance =
            IComptroller(comptroller).compAccrued(address(this));
        return rewardsBalance;
    }

    /**
     * @notice This returns unclaimed comp rewards.
     * @dev Used for testing.
     */
    function getRewardsBalance() external view returns (uint256) {
        return _getRewardsBalance();
    }

    function _claimRewards() internal {
        address[] memory markets = new address[](1);
        markets[0] = cToken;
        IComptroller(comptroller).claimComp(address(this), markets);
    }

    /**
     * @notice This claims comp rewards.
     * @dev Usually claimLiquidateAndReinvestRewards should be called instead of this. This is used for testing or if for any reason we don't want to liquidate right now.
     */
    function claimRewards() external {
        _claimRewards();
    }

    function _getRewardPriceInUnderlying() internal view returns (uint256) {
        return uint256(PriceFeedLibrary._getPrice(_rewardTokenPriceFeed));
    }

    /**
     * @notice This updates the slippage used to calculate liquidation price. This can be set by fund manager or governance.
     * @param newSlippage New slippage in BPS
     */
    function updateSlippage(uint256 newSlippage)
        external
        onlyFundManagerOrGovernance
    {
        require(newSlippage > 0, "The slippage should be greater than 0");
        require(
            newSlippage < MAX_BPS,
            "The slippage should be less than 10000"
        );
        allowedSlippage = newSlippage;
    }

    /**
     * @notice This uses price feed to get minimum balance of underlying expected during liquidation of rewards.
     * @dev The slippage can be set by fund manager or governance.
     * @return Minimum underlying expected when liquidating rewards.
     */
    function _getMinUnderlyingExpectedFromRewards()
        internal
        view
        returns (uint256)
    {
        uint256 rewardPriceInUnderlying = _getRewardPriceInUnderlying();
        uint256 rewardAmount = IERC20(rewardToken).balanceOf(address(this));
        uint256 minUnderlyingExpected =
            rewardPriceInUnderlying
                .mul(
                rewardAmount.sub(rewardAmount.mul(allowedSlippage).div(MAX_BPS))
            )
                .mul(10**uint256(ERC20(underlying).decimals()))
                .div(
                10 **
                    uint256(
                        PriceFeedLibrary._getDecimals(_rewardTokenPriceFeed)
                    )
            )
                .div(10**uint256(ERC20(rewardToken).decimals()));
        return minUnderlyingExpected;
    }

    /**
     * @notice This liquidates all the reward token to underlying and reinvests.
     * @dev This does not claim the rewards.
     */
    function _liquidateRewards() internal {
        uint256 minUnderlyingExpected = _getMinUnderlyingExpectedFromRewards();
        SwapTokensLibrary._liquidateRewards(
            rewardToken,
            underlying,
            _dEXRouter,
            _baseCurrency,
            minUnderlyingExpected
        );
    }

    /**
     * @notice This claims the rewards, liquidates all the reward token to underlying and reinvests.
     * @dev This is same as hardwork, but can be called externally (without fund)
     */
    function claimLiquidateAndReinvestRewards()
        external
        onlyFundManagerOrRelayer
    {
        _claimRewards();
        _liquidateRewards();
        _investAllUnderlying();
    }

    /**
     * @notice This gives expected base(supply) APR after depositing more amount to the strategy.
     * This is used in the optimizer strategy to decide where to invest.
     * @param depositAmount New amount to deposit in the strategy
     * @return Yearly net rate multiplied by 10**6
     */
    function baseAprAfterDeposit(uint256 depositAmount)
        public
        view
        returns (uint256)
    {
        WhitePaperInterestRateModel white =
            WhitePaperInterestRateModel(ICToken(cToken).interestRateModel());
        uint256 ratePerBlock =
            white.getSupplyRate(
                ICToken(cToken).getCash().add(depositAmount),
                ICToken(cToken).totalBorrows(),
                ICToken(cToken).totalReserves(),
                ICToken(cToken).reserveFactorMantissa()
            );
        return ratePerBlock.mul(BLOCKS_PER_YEAR).mul(APR_BASE).div(PRECISION);
    }

    /**
     * @notice This gives expected reward APR after depositing more amount to the strategy.
     * This is used in the optimizer strategy to decide where to invest.
     * @param depositAmount New amount to deposit in the strategy
     * @return Yearly net rate multiplied by 10**6
     */
    function rewardAprAfterDeposit(uint256 depositAmount)
        public
        view
        returns (uint256)
    {
        uint256 compSpeed = IComptroller(comptroller).compSpeeds(cToken); // Will divide by PRECISION at last step to keep calculations reliable
        uint256 cTokenSupply = IERC20(cToken).totalSupply().add(_shareValueFromUnderlying(depositAmount)); // Divided by decimals at next step
        uint256 compPerUnderlyingPerBlock =
            compSpeed
                .mul(PRECISION) // Scaling factor for exchangeRateStored
                .mul(10**uint256(ERC20(underlying).decimals()))
                .div(cTokenSupply)
                .div(ICToken(cToken).exchangeRateStored());
        uint256 rewardRatePerBlock =
            _getRewardPriceInUnderlying().mul(compPerUnderlyingPerBlock).div(
                10 **
                    uint256(
                        PriceFeedLibrary._getDecimals(_rewardTokenPriceFeed)
                    )
            );
        return (
            rewardRatePerBlock.mul(BLOCKS_PER_YEAR).mul(APR_BASE).div(PRECISION)
        );
    }

    /**
     * @notice This gives expected APR after depositing more amount to the strategy.
     * This is used in the optimizer strategy to decide where to invest.
     * @param depositAmount New amount to deposit in the strategy
     * @return Yearly net rate multiplied by 10**6
     */
    function aprAfterDeposit(uint256 depositAmount)
        public
        view
        override
        returns (uint256)
    {
        return baseAprAfterDeposit(depositAmount).add(rewardAprAfterDeposit(depositAmount));
    }

    /**
     * @notice This gives current base(supply) APR of the strategy
     * @return Yearly net rate mulltiplied by 10**6
     */
    function baseApr() external view returns (uint256) {
        return baseAprAfterDeposit(0);
    }

    /**
     * @notice This gives current COMP APR of the strategy.
     * @return Yearly net rate multiplied by 10**6
     */
    function rewardApr() external view returns (uint256) {
        return rewardAprAfterDeposit(0);
    }

    /**
     * @notice This gives current APR of the strategy including supply apr and rewards apr
     * @return Yearly net rate mulltiplied by 10**6
     */
    function apr() external view override returns (uint256) {
        return aprAfterDeposit(0);
    }

    /**
     * @notice No tokens apart from underlying assets, shares and rewards should ever be stored on this contract.
     * Any tokens that are sent here by mistake are recoverable by owner.
     * @dev Not applicable for ETH, different function needs to be written
     * @param  _token  Token address that needs to be recovered
     * @param  _sweepTo  Address to which tokens are sent
     */
    function sweep(address _token, address _sweepTo) external {
        require(_governance() == msg.sender, "Not governance");
        require(!canNotSweep[_token], "Token is restricted");
        require(_sweepTo != address(0), "can not sweep to zero");
        IERC20(_token).safeTransfer(
            _sweepTo,
            IERC20(_token).balanceOf(address(this))
        );
    }
}
