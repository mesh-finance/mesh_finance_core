// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

/// @title Lending strategy for DyDx
/// @author Mesh Finance
/// @notice This strategy lends asset to DYDX
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/Math.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/SafeMath.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/IERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/utils/Address.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/SafeERC20.sol";
import "../../../interfaces/strategies/DyDxStrategies/IDyDx.sol";
import "../../../interfaces/strategies/DyDxStrategies/IInterestSetter.sol";
import "../../../interfaces/IFund.sol";
import "../../../interfaces/IStrategy.sol";
import "../../../interfaces/IStrategyUnderOptimizer.sol";
import "../../../interfaces/IGovernable.sol";
import "../../../interfaces/strategies/DyDxStrategies/DyDxStructs.sol";

abstract contract DyDxLendingStrategyBase is
    DyDxStructs,
    IStrategy,
    IStrategyUnderOptimizer
{
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    uint256 internal constant APR_BASE = 10**6;

    uint256 public constant secondsInAYear = 31536000;

    address public immutable override underlying; /// underlying asset of the strategy
    address public immutable override fund; /// fund which deployed this strategy
    address public immutable override creator; /// creator of the strategy

    address public constant dydxAddressesProvider =
        address(0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e); /// solmargin contract from DyDx. This is where we lend assets.
    IDyDx internal dydx = IDyDx(dydxAddressesProvider); /// Object to interact with above contract's functions
    uint256 public immutable marketId; /// market id for DyDx pool 0 for ETH, 2 for USDC, 3 for DAI

    /// these tokens cannot be swept by the governance
    mapping(address => bool) public canNotSweep;

    bool public investActivated; /// if false, this contract doesn't lend any new assets to DyDx

    /// @notice Deploys the lending strategy for DyDx for a particular fund and underlying asset
    /// @param _fund is the address of the fund adding this strategy
    /// @param _marketId decides which asset are we deploying this strategy for. 0 for ETH, 2 for USDC, 3 for DAI
    constructor(address _fund, uint256 _marketId) public {
        require(_fund != address(0), "Fund cannot be empty");
        fund = _fund;
        address _underlying = IFund(_fund).underlying();
        // the underlying asset of the strategy should match the underlying asset of the dydx market
        require(
            _underlying == dydx.getMarketTokenAddress(_marketId),
            "Underlying do not match"
        );
        underlying = _underlying;
        marketId = _marketId;
        creator = msg.sender;

        // undelying asset of this strategy can not be swept by the governance
        canNotSweep[_underlying] = true;
        investActivated = true;
    }

    /// @return the ERC20 address of the governance
    function _governance() internal view returns (address) {
        return IGovernable(fund).governance();
    }

    /// @return the ERC20 address of the fund manager
    function _fundManager() internal view returns (address) {
        return IFund(fund).fundManager();
    }

    /// @return the ERC20 address of the Relayer
    function _relayer() internal view returns (address) {
        return IFund(fund).relayer();
    }

    /// used to restrict access of functions to only Fund
    modifier onlyFund() {
        require(msg.sender == fund, "The sender has to be the fund");
        _;
    }

    /// used to restrict access of functions to either Fund or Governance
    modifier onlyFundOrGovernance() {
        require(
            msg.sender == fund || msg.sender == _governance(),
            "The sender has to be the governance or fund"
        );
        _;
    }

    /// used to restrict access of functions to either Fund Manager or Governance
    modifier onlyFundManagerOrGovernance() {
        require(
            msg.sender == _fundManager() || msg.sender == _governance(),
            "The sender has to be the governance or fund manager"
        );
        _;
    }

    /// used to restrict access of functions to either Fund Manager or Relayer
    modifier onlyFundManagerOrRelayer() {
        require(
            msg.sender == _fundManager() || msg.sender == _relayer(),
            "The sender has to be the relayer or fund manager"
        );
        _;
    }

    /**
     * Allows Governance or Fund Manager to withdraw partial lent underlying balance from DyDx to reduce slippage incurred
     *  and facilitate migration / withdrawal / strategy switch
     * @param underlyingAmountToWithdraw is the lent underlying amount you want to withdraw from DyDx
     * @dev check if it can be converted into withdrawPartialShares using AssetDenomination Par
     */
    function withdrawPartialFund(uint256 underlyingAmountToWithdraw)
        external
        onlyFundManagerOrGovernance
    {
        Info[] memory infos = new Info[](1);
        infos[0] = Info(address(this), 0);
        AssetAmount memory amount =
            AssetAmount(
                false,
                AssetDenomination.Wei,
                AssetReference.Delta,
                underlyingAmountToWithdraw
            );
        bytes memory emptyData;
        ActionArgs[] memory actions = new ActionArgs[](1);
        actions[0] = ActionArgs(
            ActionType.Withdraw,
            0,
            amount,
            marketId,
            0,
            address(this),
            0,
            emptyData
        );
        dydx.operate(infos, actions);
    }

    /// @notice Allows Fund Manager or Governance to activate or deactivate lending for DyDx
    /// @param _investActivated the current state of whether the lending to DyDx is activated or not
    function setInvestActivated(bool _investActivated)
        external
        onlyFundManagerOrGovernance
    {
        investActivated = _investActivated;
    }

    /**
     * @notice Withdraws an underlying asset from the strategy to the fund in the specified amount.
     * Only Fund can call this function
     * It tries to withdraw from the strategy contract if this has enough balance.
     * Otherwise, we withdraw the required funds from the DyDx to the strategy and transfer it to fund
     * @param underlyingAmount is the underlying amount you want to withdraw from this strategy to Fund
     */
    function withdrawToFund(uint256 underlyingAmount)
        external
        override
        onlyFund
    {
        uint256 underlyingBalanceBefore =
            IERC20(underlying).balanceOf(address(this));
        // If the strategy already has the required amount of the underlying asset,just withdraw it to the fund
        if (underlyingBalanceBefore >= underlyingAmount) {
            IERC20(underlying).safeTransfer(fund, underlyingAmount);
            return;
        }

        uint256 underlyingAmountToWithdraw =
            underlyingAmount.sub(underlyingBalanceBefore); // If strategy doesn't have enough balance then withdraw the rest from the DyDx protocol

        // withdraw underlying from DYDX
        Info[] memory infos = new Info[](1);
        infos[0] = Info(address(this), 0);
        AssetAmount memory amount =
            AssetAmount(
                false,
                AssetDenomination.Wei,
                AssetReference.Delta,
                underlyingAmountToWithdraw
            );
        bytes memory emptyData;
        ActionArgs[] memory actions = new ActionArgs[](1);
        actions[0] = ActionArgs(
            ActionType.Withdraw,
            0,
            amount,
            marketId,
            0,
            address(this),
            0,
            emptyData
        );
        dydx.operate(infos, actions);

        // now we can transfer the assets to the fund
        uint256 underlyingBalance = IERC20(underlying).balanceOf(address(this));
        if (underlyingBalance > 0) {
            if (underlyingAmount < underlyingBalance) {
                IERC20(underlying).safeTransfer(fund, underlyingAmount);
                _investAllUnderlying();
            } else {
                // if we are still short the balance that needs to be withdrawn, we just withdraw all the available balance to the fund
                IERC20(underlying).safeTransfer(fund, underlyingBalance);
            }
        }
    }

    /**
     * @notice Withdraws all underlying balance from this strategy to fund.
     * First we withdraw all the lent underlying amount from DyDx to the strategy
     * Then we transfer all the underlying in the strategy to fund
     * Only Fund can call this function
     */
    function withdrawAllToFund() external override onlyFund {
        // withdraw all the underlying from DYDX to the strategy
        Info[] memory infos = new Info[](1);
        infos[0] = Info(address(this), 0);
        AssetAmount memory amount =
            AssetAmount(false, AssetDenomination.Par, AssetReference.Target, 0);
        bytes memory emptyData;
        ActionArgs[] memory actions = new ActionArgs[](1);
        actions[0] = ActionArgs(
            ActionType.Withdraw,
            0,
            amount,
            marketId,
            0,
            address(this),
            0,
            emptyData
        );
        dydx.operate(infos, actions);

        // Transfer all the underlying assets from strategy to the fund
        uint256 underlyingBalance = IERC20(underlying).balanceOf(address(this));
        if (underlyingBalance > 0) {
            IERC20(underlying).safeTransfer(fund, underlyingBalance);
        }
    }

    /**
     * lend all underlying assets to DyDx.
     */
    function _investAllUnderlying() internal {
        if (!investActivated) {
            return;
        }

        uint256 underlyingBalance = IERC20(underlying).balanceOf(address(this));
        if (underlyingBalance > 0) {
            // DyDx implementation for deposit
            Info[] memory infos = new Info[](1);
            infos[0] = Info(address(this), 0);
            AssetAmount memory amount =
                AssetAmount(
                    true,
                    AssetDenomination.Wei,
                    AssetReference.Delta,
                    underlyingBalance
                );
            bytes memory emptyData;
            ActionArgs[] memory actions = new ActionArgs[](1);
            actions[0] = ActionArgs(
                ActionType.Deposit,
                0,
                amount,
                marketId,
                0,
                address(this),
                0,
                emptyData
            );
            IERC20(underlying).approve(dydxAddressesProvider, 0);
            IERC20(underlying).approve(
                dydxAddressesProvider,
                underlyingBalance
            );
            dydx.operate(infos, actions);
        }
    }

    /**
     * The hard work only invests all underlying assets
     * Lend all the underlying to DyDx
     * Only fund can call this function
     */
    function doHardWork() external override onlyFund {
        _investAllUnderlying();
    }

    /// calculates what will the APR be after depositing a specific underlyign amount
    /// @param depositAmount the amount you want to deposit to the underlying protocol
    function _aprAfterDeposit(uint256 depositAmount)
        internal
        view
        returns (uint256)
    {
        uint256 precision = 10**18;
        (uint256 borrow, uint256 supply) = dydx.getMarketTotalPar(marketId);
        (uint256 borrowIndex, uint256 supplyIndex) =
            dydx.getMarketCurrentIndex(marketId);
        borrow = borrow.mul(borrowIndex).div(precision);
        supply = supply.mul(supplyIndex).div(precision);
        uint256 usage = borrow.mul(precision).div(supply.add(depositAmount));
        uint256 borrowRatePerSecond =
            IInterestSetter(dydx.getMarketInterestSetter(marketId))
                .getInterestRate(underlying, borrow, supply.add(depositAmount));
        uint256 aprBorrow = borrowRatePerSecond.mul(secondsInAYear);
        return
            aprBorrow
                .mul(usage)
                .mul(dydx.getEarningsRate())
                .mul(APR_BASE)
                .div(precision)
                .div(precision)
                .div(10**18);
    }

    /**
     * This gives expected APR after depositing a new amount to the strategy.
     * This is used in the optimizer strategy to decide where to invest.
     * Copied from idle compound wrapper
     * @param depositAmount new amount we want to lend to DyDx
     * @return returns the APR value in BPS (percent multipied by 10000)
     */
    function aprAfterDeposit(uint256 depositAmount)
        external
        view
        override
        returns (uint256)
    {
        return _aprAfterDeposit(depositAmount);
    }

    /**
     * This gives current APR of the strategy.
     * Copied from idle compound wrapper
     * @return returns the APR value in BPS (percent multiplied by 10000)
     */
    function apr() external view override returns (uint256) {
        return _aprAfterDeposit(0);
    }

    // no tokens apart from underlying should be sent to this contract. Any tokens that are sent here by mistake are recoverable by governance
    /// @param _token is the ERC20 address of the token we want to withdraw
    /// @param _sweepTo is the ERC20 address of the account we want to send tokens to
    /// @dev should we create a onlyGovernance function like onlyFundManager and use it here?
    function sweep(address _token, address _sweepTo) external {
        require(_governance() == msg.sender, "Not governance");
        require(!canNotSweep[_token], "Token is restricted");
        require(_sweepTo != address(0), "can not sweep to zero");
        IERC20(_token).safeTransfer(
            _sweepTo,
            IERC20(_token).balanceOf(address(this))
        );
    }

    /**
        Returns the underlying invested balance. This is the underlying amount based on the accounting of dydx solo
        margin contracts
        plus the current balance of the underlying asset.
        @return returns the invested underlying balance multipled by underlying's decimal value 
    */
    function investedUnderlyingBalance()
        external
        view
        override
        returns (uint256)
    {
        (, uint256 _value) =
            dydx.getAccountWei(Info(address(this), 0), marketId);
        return _value.add(IERC20(underlying).balanceOf(address(this)));
    }

    /**
     * @notice Returns the value of the underlying token in DyDx. It has been used only for tests till now.
     * @return Returns the current value of the underlying lent to DyDx multipled by underlying's decimal value
     */
    function underlyingValueInDyDx() external view returns (uint256) {
        (, uint256 _value) =
            dydx.getAccountWei(Info(address(this), 0), marketId);
        return _value;
    }
}
