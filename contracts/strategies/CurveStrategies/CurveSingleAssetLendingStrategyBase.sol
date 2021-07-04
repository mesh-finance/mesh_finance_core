// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/Math.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/SafeMath.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/IERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/utils/Address.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/SafeERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/ERC20.sol";
import "../../../interfaces/strategies/CurveStrategies/ICurveFi.sol";
import "../../../interfaces/strategies/CurveStrategies/ICurveGauge.sol";
import "../../../interfaces/uniswap/IUniswapV2Router02.sol";
import "../../../interfaces/IFund.sol";
import "../../../interfaces/IStrategy.sol";
import "../../../interfaces/IGovernable.sol";
import "../../utils/SwapTokensLibrary.sol";
import "../../utils/PriceFeedLibrary.sol";

/**
 * This strategy takes an asset (DAI, USDC, USDT), lends to Curve Pool.
 */
abstract contract CurveSingleAssetLendingStrategyBase is IStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    using SafeMath for int128;
    using SafeMath for uint8;

    address public immutable override underlying;
    address public immutable override fund;
    address public immutable override creator;

    // the curve pool corresponding to the underlying
    address public immutable crvPool;

    // the curve token corresponding to the crvPool
    address public immutable crvPoolToken;

    // Does the curve pool have wrapped tokens?
    bool public immutable isWrappedPool;

    // If it is wrapped, are we depositing underlying tokens or wrapped tokens?
    bool public immutable useUnderlying;

    // the  id corresponding to the underlying in crvPool
    uint8 public immutable crvId;

    // CRV Token
    // solhint-disable-next-line var-name-mixedcase
    address public immutable CRVToken;

    // Reward Token
    address public immutable rewardToken;

    // Price feed for reward token
    address public immutable rewardTokenPriceFeed;

    // Gauge, for staking crvpool token, and claiming rewards
    address public crvPoolGauge;

    // Gauge type. Rewards: {1: Only CRV, 2: CRV + Reward, 3: Only Reward}
    uint8 public immutable crvPoolGaugeType;

    // DEX router to liquidate rewards to underlying
    address internal immutable _dEXRouter;

    // base currency serves as path to convert rewards to underlying
    address internal immutable _baseCurrency;

    uint256 internal allowedSlippage = 500; // In BPS, can be changed

    uint256 internal constant MAX_BPS = 10000;

    // these tokens cannot be claimed by the governance
    mapping(address => bool) public canNotSweep;

    bool public investActivated;

    constructor(
        address _fund,
        address _crvPool,
        address _crvPoolToken,
        address _crvPoolGauge,
        uint8 _crvPoolGaugeType,
        // solhint-disable-next-line var-name-mixedcase
        address _CRVToken,
        address _rewardToken,
        address _rewardTokenPriceFeed,
        address dEXRouter_,
        address baseCurrency_,
        bool _isWrappedPool,
        bool _useUnderlying
    ) public {
        require(_fund != address(0), "Fund cannot be empty");
        fund = _fund;
        address _underlying = IFund(_fund).underlying();
        underlying = _underlying;
        uint8 _crvId = type(uint8).max;

        if (!(_isWrappedPool) || (_isWrappedPool && !(_useUnderlying))) {
            if (ICurveFi(_crvPool).coins(0) == _underlying) {
                _crvId = 0;
            } else if (ICurveFi(_crvPool).coins(1) == _underlying) {
                _crvId = 1;
            } else if (ICurveFi(_crvPool).coins(2) == _underlying) {
                _crvId = 2;
            }
        } else {
            if (ICurveFi(_crvPool).underlying_coins(0) == _underlying) {
                _crvId = 0;
            } else if (ICurveFi(_crvPool).underlying_coins(1) == _underlying) {
                _crvId = 1;
            } else if (ICurveFi(_crvPool).underlying_coins(2) == _underlying) {
                _crvId = 2;
            }
        }

        require(_crvId < 3, "Incorrect curve pool");
        crvId = _crvId;
        crvPool = _crvPool;
        crvPoolGaugeType = _crvPoolGaugeType;
        crvPoolToken = _crvPoolToken;
        isWrappedPool = _isWrappedPool;
        useUnderlying = _useUnderlying;
        crvPoolGauge = _crvPoolGauge;
        CRVToken = _CRVToken;
        rewardToken = _rewardToken;
        rewardTokenPriceFeed = _rewardTokenPriceFeed;
        _dEXRouter = dEXRouter_;
        _baseCurrency = baseCurrency_;
        creator = msg.sender;

        // approve max amount to save on gas costs later
        IERC20(_underlying).safeApprove(_crvPool, type(uint256).max);
        IERC20(_crvPoolToken).safeApprove(_crvPoolGauge, type(uint256).max);

        // restricted tokens, can not be swept
        canNotSweep[_underlying] = true;
        canNotSweep[_crvPoolToken] = true;
        canNotSweep[_crvPoolGauge] = true;
        canNotSweep[_CRVToken] = true;
        canNotSweep[_rewardToken] = true;

        investActivated = true;
    }

    function _governance() internal view returns (address) {
        return IGovernable(fund).governance();
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

    modifier onlyFundOrGovernanceorRelayer() {
        require(
            msg.sender == fund ||
                msg.sender == _governance() ||
                msg.sender == _relayer(),
            "The sender has to be the governance or fund or relayer"
        );
        _;
    }

    /**
     *  TODO
     */
    function depositArbCheck() public view override returns (bool) {
        return true;
    }

    function setInvestActivated(bool _investActivated)
        external
        onlyFundOrGovernance
    {
        investActivated = _investActivated;
    }

    function _withdrawCrvPoolTokens(uint256 _requiredCrvPoolTokens) internal {
        if (_requiredCrvPoolTokens > 0) {
            ICurveGauge(crvPoolGauge).withdraw(_requiredCrvPoolTokens);
            uint256 expectedOut =
                ICurveFi(crvPool).calc_withdraw_one_coin(
                    _requiredCrvPoolTokens,
                    int128(crvId)
                );
            uint256 minOut =
                expectedOut.mul(MAX_BPS.sub(allowedSlippage)).div(MAX_BPS);

            if (!(isWrappedPool) || (isWrappedPool && !(useUnderlying))) {
                ICurveFi(crvPool).remove_liquidity_one_coin(
                    _requiredCrvPoolTokens,
                    int128(crvId),
                    minOut
                );
            } else {
                ICurveFi(crvPool).remove_liquidity_one_coin(
                    _requiredCrvPoolTokens,
                    int128(crvId),
                    minOut,
                    true
                );
            }
        }
    }

    /**
     * Allows Governance to withdraw partial shares to reduce slippage incurred
     *  and facilitate migration / withdrawal / strategy switch
     */
    function withdrawPartialShares(uint256 _crvPoolTokens)
        external
        onlyFundOrGovernance
    {
        _withdrawCrvPoolTokens(_crvPoolTokens);
    }

    /**
     * Withdraws an underlying asset from the strategy to the fund in the specified amount.
     * It tries to withdraw from the strategy contract if this has enough balance.
     * Otherwise, we withdraw from Curve to the strategy and transfer required balance to fund
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

        uint256[3] memory amounts;
        amounts[crvId] = underlyingAmount;
        uint256 _requiredCrvPoolTokens =
            ICurveFi(crvPool).calc_token_amount(amounts, false);
        uint256 _totalCrvPoolTokens =
            IERC20(crvPoolGauge).balanceOf(address(this));

        if (_requiredCrvPoolTokens > _totalCrvPoolTokens) {
            //can't withdraw more than we have
            _requiredCrvPoolTokens = _totalCrvPoolTokens;
        }

        _withdrawCrvPoolTokens(_requiredCrvPoolTokens);

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
     * Withdraws all assets from the Curve Pool to fund.
     */
    function withdrawAllToFund() external override onlyFundOrGovernance {
        uint256 _crvPoolTokens = IERC20(crvPoolGauge).balanceOf(address(this));
        _withdrawCrvPoolTokens(_crvPoolTokens);

        uint256 underlyingBalance = IERC20(underlying).balanceOf(address(this));
        if (underlyingBalance > 0) {
            IERC20(underlying).safeTransfer(fund, underlyingBalance);
        }
    }

    /**
     * Invests all underlying assets into our curve.
     */
    function _investAllUnderlying() internal {
        if (!investActivated) {
            return;
        }

        uint256 underlyingBalance = IERC20(underlying).balanceOf(address(this));
        if (underlyingBalance > 0) {
            uint256[3] memory amounts;
            amounts[crvId] = underlyingBalance;
            uint256 expectedOut =
                ICurveFi(crvPool).calc_token_amount(amounts, true);
            uint256 minOut =
                expectedOut.mul(MAX_BPS.sub(allowedSlippage)).div(MAX_BPS);

            if (!(isWrappedPool) || (isWrappedPool && !(useUnderlying))) {
                ICurveFi(crvPool).add_liquidity(amounts, minOut);
            } else {
                ICurveFi(crvPool).add_liquidity(amounts, minOut, true);
            }
        }

        // deposit lptokens to the gauge
        uint256 crvPoolTokens = IERC20(crvPoolToken).balanceOf(address(this));
        if (crvPoolTokens > 0) {
            ICurveGauge(crvPoolGauge).deposit(crvPoolTokens);
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

    function _getCRVRewardsBalance() internal returns (uint256) {
        uint256 crvRewardsBalance;
        if (crvPoolGaugeType == 1 || crvPoolGaugeType == 2) {
            crvRewardsBalance = ICurveGauge(crvPoolGauge).claimable_tokens(
                address(this)
            );
        }
        return crvRewardsBalance;
    }

    function getCRVRewardsBalance() external returns (uint256) {
        return _getCRVRewardsBalance();
    }

    function _getRewardsBalance() internal returns (uint256) {
        uint256 rewardsBalance;
        if (crvPoolGaugeType == 2 || crvPoolGaugeType == 3) {
            rewardsBalance = ICurveGauge(crvPoolGauge).claimable_reward(
                address(this),
                rewardToken
            );
        }
        return rewardsBalance;
    }

    // This will claim rewards, as it is called as a transaction
    function getRewardsBalance() external returns (uint256) {
        return _getRewardsBalance();
    }

    function _claimCRVRewards() internal returns (uint256) {
        uint256 crvRewardsBalanceToClaim = _getCRVRewardsBalance();
        uint256 crvRewardsBalanceClaimed;
        crvRewardsBalanceClaimed = crvRewardsBalanceToClaim;
        // TO DO, not needed for Polygon
        return crvRewardsBalanceClaimed;
    }

    function claimCRVRewards() external returns (uint256) {
        return _claimCRVRewards();
    }

    function _claimRewards() internal {
        if (crvPoolGaugeType == 2 || crvPoolGaugeType == 3) {
            ICurveGauge(crvPoolGauge).claim_rewards(address(this));
        }
    }

    function claimRewards() external {
        _claimRewards();
    }

    function _getRewardPriceInUnderlying() internal view returns (uint256) {
        return uint256(PriceFeedLibrary._getPrice(rewardTokenPriceFeed));
    }

    function updateSlippage(uint256 newSlippage) external onlyFundOrGovernance {
        require(newSlippage > 0, "The slippage should be greater than 0");
        require(
            newSlippage < MAX_BPS,
            "The slippage should be less than 10000"
        );
        allowedSlippage = newSlippage;
    }

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
                10**uint256(PriceFeedLibrary._getDecimals(rewardTokenPriceFeed))
            )
                .div(10**uint256(ERC20(rewardToken).decimals()));
        return minUnderlyingExpected;
    }

    function _liquidateCRVRewards() internal {
        uint256 minUnderlyingExpected = _getMinUnderlyingExpectedFromRewards(); // TODO
        SwapTokensLibrary._liquidateRewards(
            CRVToken,
            underlying,
            _dEXRouter,
            _baseCurrency,
            minUnderlyingExpected
        );
    }

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
     * This claims the rewards, liquidates all the reward token to underlying and reinvests
     */
    function claimLiquidateAndReinvestRewards()
        external
        onlyFundOrGovernanceorRelayer
    {
        // _claimCRVRewards();  // Not needed for polygon
        // _liquidateCRVRewards();  // Not needed for polygon
        _claimRewards();
        _liquidateRewards();
        _investAllUnderlying();
    }

    function _virtualPriceInUnderlying() internal view returns (uint256) {
        if (ERC20(underlying).decimals() < 18) {
            return
                ICurveFi(crvPool).get_virtual_price().div(
                    10**(uint256(uint8(18) - ERC20(underlying).decimals()))
                );
        } else {
            return ICurveFi(crvPool).get_virtual_price();
        }
    }

    /**
     * Returns the underlying invested balance. This is the underlying amount based on atoken balance,
     * plus the current balance of the underlying asset.
     */
    function investedUnderlyingBalance()
        external
        view
        override
        returns (uint256)
    {
        uint256 _crvPoolTokens = IERC20(crvPoolGauge).balanceOf(address(this));

        if (_crvPoolTokens == 0) {
            return 0;
        }

        //we want to choose lower value of virtual price and amount we really get out
        //this means we will always underestimate current assets.
        uint256 virtualOut =
            _virtualPriceInUnderlying().mul(_crvPoolTokens).div(1e18);

        uint256 realOut =
            ICurveFi(crvPool).calc_withdraw_one_coin(
                _crvPoolTokens,
                int128(crvId)
            );

        return
            Math.min(virtualOut, realOut).add(
                IERC20(underlying).balanceOf(address(this))
            );
    }
}
