// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/Math.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/SafeMath.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/IERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/utils/Address.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/SafeERC20.sol";
import "../../../interfaces/strategies/YearnV2Strategies/IYVaultV2.sol";
import "../../../interfaces/IFund.sol";
import "../../../interfaces/IStrategy.sol";
import "../../../interfaces/IGovernable.sol";

/**
 * This strategy takes an asset (DAI, USDC), deposits into yv2 vault. Currently building only for DAI.
 */
abstract contract YearnV2StrategyBase is IStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public immutable override underlying;
    address public immutable override fund;
    address public immutable override creator;

    // the y-vault corresponding to the underlying asset
    address public immutable yVault;

    // these tokens cannot be claimed by the governance
    mapping(address => bool) public canNotSweep;

    bool public investActivated;

    constructor(address _fund, address _yVault) public {
        require(_fund != address(0), "Fund cannot be empty");
        require(_yVault != address(0), "Yearn Vault cannot be empty");
        fund = _fund;
        address _underlying = IFund(_fund).underlying();
        require(
            _underlying == IYVaultV2(_yVault).token(),
            "Underlying do not match"
        );
        underlying = _underlying;
        yVault = _yVault;
        creator = msg.sender;

        // restricted tokens, can not be swept
        canNotSweep[_underlying] = true;
        canNotSweep[_yVault] = true;

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
     *  Not used for now
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
        onlyFundManagerOrGovernance
    {
        IYVaultV2(yVault).withdraw(shares);
    }

    function setInvestActivated(bool _investActivated)
        external
        onlyFundManagerOrGovernance
    {
        investActivated = _investActivated;
    }

    /**
     * Withdraws an underlying asset from the strategy to the fund in the specified amount.
     * It tries to withdraw from the strategy contract if this has enough balance.
     * Otherwise, we withdraw shares from the yv2 vault. Transfer the required underlying amount to fund,
     * and reinvest the rest. We can make it better by calculating the correct amount and withdrawing only that much.
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

        uint256 shares =
            _shareValueFromUnderlying(
                underlyingAmount.sub(underlyingBalanceBefore)
            );
        uint256 totalShares = IYVaultV2(yVault).balanceOf(address(this));

        if (shares > totalShares) {
            //can't withdraw more than we have
            shares = totalShares;
        }
        IYVaultV2(yVault).withdraw(shares);

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
     * Withdraws all assets from the yv2 vault and transfer to fund.
     */
    function withdrawAllToFund() external override onlyFund {
        uint256 shares = IYVaultV2(yVault).balanceOf(address(this));
        IYVaultV2(yVault).withdraw(shares);
        uint256 underlyingBalance = IERC20(underlying).balanceOf(address(this));
        if (underlyingBalance > 0) {
            IERC20(underlying).safeTransfer(fund, underlyingBalance);
        }
    }

    /**
     * Invests all underlying assets into our yv2 vault.
     */
    function _investAllUnderlying() internal {
        if (!investActivated) {
            return;
        }

        require(
            !IYVaultV2(yVault).emergencyShutdown(),
            "Vault is emergency shutdown"
        );

        uint256 underlyingBalance = IERC20(underlying).balanceOf(address(this));
        if (underlyingBalance > 0) {
            // approve amount per transaction
            IERC20(underlying).safeApprove(yVault, 0);
            IERC20(underlying).safeApprove(yVault, underlyingBalance);
            // deposits the entire balance to yv2 vault
            IYVaultV2(yVault).deposit(underlyingBalance);
        }
    }

    /**
     * The hard work only invests all underlying assets
     */
    function doHardWork() external override onlyFund {
        _investAllUnderlying();
    }

    // no tokens apart from underlying should be sent to this contract. Any tokens that are sent here by mistake are recoverable by governance
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
     * Returns the underlying invested balance. This is the underlying amount based on shares in the yv2 vault,
     * plus the current balance of the underlying asset.
     */
    function investedUnderlyingBalance()
        external
        view
        override
        returns (uint256)
    {
        uint256 shares = IERC20(yVault).balanceOf(address(this));
        uint256 price = IYVaultV2(yVault).pricePerShare();
        uint256 precision = 10**(IYVaultV2(yVault).decimals());
        uint256 underlyingBalanceinYVault = shares.mul(price).div(precision);
        return
            underlyingBalanceinYVault.add(
                IERC20(underlying).balanceOf(address(this))
            );
    }

    /**
     * Returns the value of the underlying token in yToken
     */
    function _shareValueFromUnderlying(uint256 underlyingAmount)
        internal
        view
        returns (uint256)
    {
        uint256 precision = 10**(IYVaultV2(yVault).decimals());
        return
            underlyingAmount.mul(precision).div(
                IYVaultV2(yVault).pricePerShare()
            );
    }
}
