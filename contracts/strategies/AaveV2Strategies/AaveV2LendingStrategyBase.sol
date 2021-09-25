// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/Math.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/SafeMath.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/IERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/utils/Address.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/SafeERC20.sol";
import "../../../interfaces/strategies/AaveV2Strategies/IAaveV2.sol";
import "../../../interfaces/strategies/AaveV2Strategies/IAaveIncentivesController.sol";
import "../../../interfaces/uniswap/IUniswapV2Router02.sol";
import "../../../interfaces/IFund.sol";
import "../../../interfaces/IStrategy.sol";
import "../../../interfaces/IStrategyUnderOptimizer.sol";
import "../../../interfaces/IGovernable.sol";
import "../../utils/SwapTokensLibrary.sol";

/**
 * @title Lending strategy for Aave V2
 * @author Mesh Finance
 * @notice This strategy lends asset to Aave V2
 */
abstract contract AaveV2LendingStrategyBase is
    IStrategy,
    IStrategyUnderOptimizer
{
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    uint256 internal constant APR_BASE = 10**6;

    address public immutable override underlying;
    address public immutable override fund;
    address public immutable override creator;

    // Address provider for AAVE
    AaveLendingPoolAddressesProviderV2 public immutable aaveAddressesProvider;

    // the aToken corresponding to the underlying
    address public immutable aToken;

    // Reward Token
    address public immutable rewardToken;

    // Unstaked Reward Token
    address public immutable unstakedRewardToken;

    // Reward token controller, for claiming rewards
    address public incentivesController;

    // DEX router to liquidate rewards to underlying
    address internal immutable _dEXRouter;

    // base currency serves as path to convert rewards to underlying
    address internal immutable _baseCurrency;

    // these tokens cannot be claimed by the governance
    mapping(address => bool) public canNotSweep;

    bool public investActivated;

    constructor(
        address _fund,
        address aaveAddressProvider_,
        address _incentivesController,
        address _rewardToken,
        address _unstakedRewardToken,
        address dEXRouter_,
        address baseCurrency_
    ) public {
        require(_fund != address(0), "Fund cannot be empty");
        fund = _fund;
        address _underlying = IFund(_fund).underlying();
        underlying = _underlying;
        AaveLendingPoolAddressesProviderV2 _aaveAddressesProvider =
            AaveLendingPoolAddressesProviderV2(aaveAddressProvider_);
        aaveAddressesProvider = _aaveAddressesProvider;
        bytes32 _providerId =
            0x0100000000000000000000000000000000000000000000000000000000000000;
        address _aaveProtocolDataProvider =
            _aaveAddressesProvider.getAddress(_providerId);
        (address _aToken, , ) =
            AaveProtocolDataProviderV2(_aaveProtocolDataProvider)
                .getReserveTokensAddresses(_underlying);
        //TODO: Check if we can add a require statement to check underlyign from Aave market to strategy
        aToken = _aToken;
        incentivesController = _incentivesController;
        rewardToken = _rewardToken;
        unstakedRewardToken = _unstakedRewardToken;
        _dEXRouter = dEXRouter_;
        _baseCurrency = baseCurrency_;
        creator = msg.sender;

        // restricted tokens, can not be swept
        canNotSweep[_underlying] = true;
        canNotSweep[_aToken] = true;
        canNotSweep[_rewardToken] = true;
        canNotSweep[_unstakedRewardToken] = true;

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

    modifier onlyFundOrGovernance() {
        require(
            msg.sender == fund || msg.sender == _governance(),
            "The sender has to be the governance or fund"
        );
        _;
    }

    modifier onlyFund() {
        require(msg.sender == fund, "The sender has to be the fund");
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
     * @notice Allows Governance/Fund Manager to stop/start investing assets from this strategy to AAVE V2
     * @dev Used for emergencies
     * @param _investActivated Set investment to True/False
     */
    function setInvestActivated(bool _investActivated)
        external
        onlyFundManagerOrGovernance
    {
        investActivated = _investActivated;
    }

    function _withdrawATokens(uint256 _requiredATokens) internal {
        if (_requiredATokens > 0) {
            address _aaveLendingPool = aaveAddressesProvider.getLendingPool();
            AaveLendingPoolV2(_aaveLendingPool).withdraw(
                underlying,
                _requiredATokens,
                address(this)
            );
        }
    }

    /**
     * @notice Allows Governance/Fund manager to withdraw partial shares to reduce slippage incurred
     * and facilitate migration / withdrawal / strategy switch
     * @param _aTokens aTokens to withdraw
     */
    function withdrawPartialShares(uint256 _aTokens)
        external
        onlyFundManagerOrGovernance
    {
        _withdrawATokens(_aTokens);
    }

    /**
     * @notice Withdraws an underlying asset from the strategy to the fund in the specified amount.
     * It tries to withdraw from the strategy contract if this has enough balance.
     * Otherwise, we withdraw from Aave V2. Transfer the required underlying amount to fund.
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

        uint256 _requiredATokens =
            _shareValueFromUnderlying(
                underlyingAmount.sub(underlyingBalanceBefore)
            );
        uint256 _totalATokens = IERC20(aToken).balanceOf(address(this));

        if (_requiredATokens > _totalATokens) {
            //can't withdraw more than we have
            _requiredATokens = _totalATokens;
        }

        _withdrawATokens(_requiredATokens);

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
     * @notice Withdraws all assets from Aave V2 and transfers all underlying to fund.
     */
    function withdrawAllToFund() external override onlyFund {
        uint256 _aTokens = IERC20(aToken).balanceOf(address(this));
        _withdrawATokens(_aTokens);

        uint256 underlyingBalance = IERC20(underlying).balanceOf(address(this));
        if (underlyingBalance > 0) {
            IERC20(underlying).safeTransfer(fund, underlyingBalance);
        }
    }

    /**
     * @notice Invests all underlying assets into Aave V2.
     */
    function _investAllUnderlying() internal {
        if (!investActivated) {
            return;
        }

        address _aaveLendingPool = aaveAddressesProvider.getLendingPool();
        uint256 underlyingBalance = IERC20(underlying).balanceOf(address(this));
        if (underlyingBalance > 0) {
            IERC20(underlying).safeApprove(_aaveLendingPool, 0);
            IERC20(underlying).safeApprove(_aaveLendingPool, underlyingBalance);

            AaveLendingPoolV2(_aaveLendingPool).deposit(
                underlying,
                underlyingBalance,
                address(this),
                0
            );
        }
    }

    /**
     * @notice This invests all the underlying balance to Aave V2.
     */
    function doHardWork() external override onlyFund {
        _investAllUnderlying();
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
        IERC20(_token).safeTransfer(
            _sweepTo,
            IERC20(_token).balanceOf(address(this))
        );
    }

    function _getRewardsBalance() internal view returns (uint256) {
        address[] memory assets = new address[](1);
        assets[0] = aToken;
        uint256 rewardsBalance =
            IAaveIncentivesController(incentivesController).getRewardsBalance(
                assets,
                address(this)
            );
        return rewardsBalance;
    }

    /**
     * @notice This returns unclaimed stkAave rewards.
     * @dev Used for testing.
     */
    function getRewardsBalance() external view returns (uint256) {
        return _getRewardsBalance();
    }

    function _claimRewards() internal returns (uint256) {
        address[] memory assets = new address[](1);
        assets[0] = aToken;
        uint256 rewardsBalanceToClaim = _getRewardsBalance();
        uint256 rewardsBalanceClaimed;
        if (rewardsBalanceToClaim > 0) {
            rewardsBalanceClaimed = IAaveIncentivesController(
                incentivesController
            )
                .claimRewards(assets, rewardsBalanceToClaim, address(this));
        }
        return rewardsBalanceClaimed;
    }

    /**
     * @notice This claims stkAave rewards.
     */
    function claimRewards() external returns (uint256) {
        return _claimRewards();
    }

    function _liquidateRewardsAndReinvest(uint256 minUnderlyingExpected)
        internal
    {
        SwapTokensLibrary._liquidateRewards(
            rewardToken,
            underlying,
            _dEXRouter,
            _baseCurrency,
            minUnderlyingExpected
        );
        _investAllUnderlying();
    }

    /**
     * @notice This liquidates all the reward token to underlying and reinvests.
     * @dev This does not claim the rewards.
     */
    function liquidateRewardsAndReinvest(uint256 minUnderlyingExpected)
        external
        onlyFundManagerOrRelayer
    {
        _liquidateRewardsAndReinvest(minUnderlyingExpected);
    }

    /**
     * @notice Returns the underlying invested balance. This is the underlying amount in aTokens, plus the current balance of the underlying asset.
     * @return Total balance invested in the strategy
     */
    function investedUnderlyingBalance()
        external
        view
        override
        returns (uint256)
    {
        uint256 _aTokens = IERC20(aToken).balanceOf(address(this));
        return _aTokens.add(IERC20(underlying).balanceOf(address(this)));
    }

    /**
     * Returns the value of the underlying token in aToken
     */
    function _shareValueFromUnderlying(uint256 underlyingAmount)
        internal
        pure
        returns (uint256)
    {
        return underlyingAmount;
    }

    /**
     * @notice This gives expected APR after depositing more amount to the strategy.
     * This is used in the optimizer strategy to decide where to invest.
     * Copied from idle aave wrapper
     * @param _amount : new underlying amount supplied (USDC)
     * @return : yearly net rate mulltiplied by 10**6
     */
    function aprAfterDeposit(uint256 _amount)
        external
        view
        override
        returns (uint256)
    {
        AaveLendingPoolV2 core =
            AaveLendingPoolV2(aaveAddressesProvider.getLendingPool());
        DataTypes.ReserveData memory data = core.getReserveData(underlying);
        AaveInterestRateStrategyV2 apr =
            AaveInterestRateStrategyV2(data.interestRateStrategyAddress);

        (uint256 totalStableDebt, uint256 avgStableRate) =
            IStableDebtToken(data.stableDebtTokenAddress)
                .getTotalSupplyAndAvgRate();

        uint256 totalVariableDebt =
            IVariableDebtToken(data.variableDebtTokenAddress)
                .scaledTotalSupply()
                .mul(data.variableBorrowIndex)
                .div(10**27);

        uint256 availableLiquidity =
            IERC20(underlying).balanceOf(data.aTokenAddress);

        (uint256 newLiquidityRate, , ) =
            apr.calculateInterestRates(
                underlying,
                availableLiquidity.add(_amount),
                totalStableDebt,
                totalVariableDebt,
                avgStableRate,
                _getReserveFactor(data.configuration)
            );
        // aave gives liquidity rate in ray unit (10**27)
        return newLiquidityRate.mul(APR_BASE).div(10**27); //yearly net rate mulltiplied by 10**6
    }

    /**
     * @notice This gives current APR of the strategy.
     * Copied from idle aave wrapper
     * @return : yearly net rate mulltiplied by 10**6
     */
    function apr() external view override returns (uint256) {
        DataTypes.ReserveData memory data =
            AaveLendingPoolV2(aaveAddressesProvider.getLendingPool())
                .getReserveData(underlying);
        // aave gives liquidity rate in ray unit (10**27)
        return uint256(data.currentLiquidityRate).mul(APR_BASE).div(10**27); // yearly net rate mulltiplied by 10**6
    }

    // copied from https://github.com/aave/protocol-v2/blob/dbd77ad9312f607b420da746c2cb7385d734b015/contracts/protocol/libraries/configuration/ReserveConfiguration.sol#L242
    function _getReserveFactor(DataTypes.ReserveConfigurationMap memory self)
        internal
        pure
        returns (uint256)
    {
        uint256 reserveFactorMask = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFFFFFFFFFFFFFF; // prettier-ignore
        uint256 reserveFactorStartBitPosition = 64;

        return
            (self.data & ~reserveFactorMask) >> reserveFactorStartBitPosition;
    }
}
