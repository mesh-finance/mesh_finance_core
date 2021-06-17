// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/Math.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/SafeMath.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/IERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/utils/Address.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/SafeERC20.sol";
import "../../../interfaces/strategies/SushiBarStrategies/ISushiBar.sol";
import "../../../interfaces/IFund.sol";
import "../../../interfaces/IStrategy.sol";
import "../../../interfaces/IGovernable.sol";

/**
 * This strategy takes an asset (DAI, USDC), deposits into yv2 vault. Currently building only for DAI.
 */

 abstract contract SushiBarStrategyBase is IStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public immutable override underlying;
    address public immutable override fund;
    address public immutable override creator;

    address public immutable  token;

    address public constant sushibar =
        address(0x8798249c2E607446EfB7Ad49eC89dD1865Ff4272);

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
        IERC20(_underlying).safeApprove(sushibar, type(uint256).max);
 
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
        ISushiBar(sushibar).withdraw(shares);
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
        uint256 totalShares = ISushiBar(sushibar).balanceOf(address(this));

        if (shares > totalShares) {
            //can't withdraw more than we have
            shares = totalShares;
        }
       ISushiBar(sushibar).leave(shares);

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
        uint256 shares = ISushiBar(sushibar).balanceOf(address(this));
        ISushiBar(sushibar).leave(shares);
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
            ISushiBar(sushibar).enter(underlyingBalance);
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
        uint256 shares = ISushiBar(sushibar).balanceOf(address(this));
        uint256 totalSushi = IERC20(token).balanceOf(address(sushibar));
        uint256 totalShares = ISushiBar(sushibar).totalSupply();
        uint256 underlyingBalanceinSushiBar = shares.mul(totalShares).div(totalSushi);
        return  
            underlyingBalanceinSushiBar.add(
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
        uint256 totalShares = ISushiBar(sushibar).totalSupply();
        uint256 totalSushi = IERC20(token).balanceOf(address(sushibar));
        return 
            underlyingAmount.mul(totalShares).div(
                totalSushi);
            
    }

    /* function withdraw(uint256 amount) external override onlyFundOrGovernance returns (uint256 underlyingAmount) {
        uint256 totalShares = ISushiBar(sushibar).totalSupply();
        uint256 totalSushi = IERC20(token).balanceOf(address(bar));
        uint256 withdrawShare = amount.mul(totalShares) / totalSushi;
        uint256 share = ISushiBar(sushibar).balanceOf(address(this));
        if (withdrawShare > share) {
            withdrawShare = share;
        }
        ISushiBar(sushibar).leave(withdrawShare);
        underlyingAmount = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(fund, underlyingAmount);
    }*/
}

