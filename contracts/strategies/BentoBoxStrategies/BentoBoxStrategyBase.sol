// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/Math.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/SafeMath.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/IERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/utils/Address.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/SafeERC20.sol";
import "../../../interfaces/strategies/BentoBoxStrategies/IBentoBox.sol";
import "../../../interfaces/IFund.sol";
import "../../../interfaces/IStrategy.sol";
import "../../../interfaces/IGovernable.sol";

/**
 * This strategy takes an asset (DAI, USDC), deposits into yv2 vault. Currently building only for DAI.
 */
abstract contract BentoBoxStrategyBase is IStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public immutable override underlying;
    address public immutable override fund;
    address public immutable override creator;

    address public immutable  token;

    address public constant bentobox =
        address(0xF5BCE5077908a1b7370B9ae04AdC565EBd643966);

    // these tokens cannot be claimed by the governance
    mapping(address => bool) public canNotSweep;

    bool public investActivated;

    constructor(address _fund, address _token) public {
        require(_fund != address(0), "Fund cannot be empty");
        require(_token != address(0), "Yearn Vault cannot be empty");
        fund = _fund;
        address _underlying = IFund(_fund).underlying();
        require(
            _underlying == _token,
            "Underlying do not match"
        );
        underlying = _underlying;
        token = _token;
        creator = msg.sender;

        // approve max amount to save on gas costs later
        IERC20(_underlying).safeApprove(bentobox, type(uint256).max);
        IBentoBox(bentobox).registerProtocol();
        //IBentoBox(bentobox).setMasterContractApproval(_fund,address(this),true,0,0,0);

        // restricted tokens, can not be swept
        canNotSweep[_underlying] = true;
        canNotSweep[_token] = true;

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
        IBentoBox(bentobox).withdraw(shares);
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
     * Otherwise, we withdraw shares from the yv2 vault. Transfer the required underlying amount to fund,
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
        uint256 totalShares = IBentoBox(bentobox).balanceOf(token,address(this));

        if (shares > totalShares) {
            //can't withdraw more than we have
            shares = totalShares;
        }
        IBentoBox(bentobox).withdraw(shares);

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
     * Withdraws all assets from the yv2 vault and transfer to fund.
     */
    function withdrawAllToFund() external override onlyFundOrGovernance {
        uint256 shares = IBentoBox(bentobox).balanceOf(token,address(this));
        IBentoBox(bentobox).withdraw(shares);
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


        uint256 underlyingBalance = IERC20(underlying).balanceOf(address(this));
        if (underlyingBalance > 0) {
            // deposits the entire balance to yv2 vault
            IBentoBox(bentobox).deposit(token,fund,address(this),underlyingBalance,0);
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
        uint256 shares = IERC20(token).balanceOf(address(this));
        uint256 price = IBentoBox(bentobox).toAmount(token,shares,false);
        uint256 precision = 10**(18);
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
        uint256 precision = 10**(18);
        return
            underlyingAmount.mul(precision).div(
                IBentoBox(bentobox).toShare(token,underlyingAmount,false)
            );
    }
}

