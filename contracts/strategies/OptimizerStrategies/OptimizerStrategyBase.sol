// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

pragma experimental ABIEncoderV2;

import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/Math.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/SafeMath.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/IERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/utils/Address.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/SafeERC20.sol";
import "../../../interfaces/IFund.sol";
import "../../../interfaces/IStrategy.sol";
import "../../../interfaces/IStrategyUnderOptimizer.sol";
import "../../../interfaces/IGovernable.sol";

/**
 * This strategy takes an asset, and invests into the best strategy
 */
/**
 * @title This is an optimizer strategy that rotates capital to various strategies.
 * @author Mesh Finance
 * @notice This strategy takes an asset, and invests into the strategy with highest APR
 */
contract OptimizerStrategyBase is IStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    event StrategyAddedOptimizer(address indexed strategy);
    event StrategyRemovedOptimizer(address indexed strategy);
    event ActiveStrategyChangedOptimizer(address indexed strategy);

    address internal constant ZERO_ADDRESS = address(0);

    string public constant override name = "OptimizerStrategyBase";
    string public constant override version = "V1";

    address public immutable override underlying;
    address public immutable override fund;
    address public immutable deployer;

    // these tokens cannot be claimed by the governance
    mapping(address => bool) public canNotSweep;

    address[] public strategies;

    address public activeStrategy;

    bool public investActivated;

    constructor(address _fund) public {
        require(_fund != address(0), "Fund cannot be empty");
        fund = _fund;
        address _underlying = IFund(_fund).underlying();
        underlying = _underlying;
        deployer = msg.sender;

        // restricted tokens, can not be swept
        canNotSweep[_underlying] = true;

        investActivated = true;
    }

    function _governance() internal view returns (address) {
        return IGovernable(fund).governance();
    }

    function governance() external view returns (address) {
        return _governance();
    }

    function _fundManager() internal view returns (address) {
        return IFund(fund).fundManager();
    }

    function fundManager() external view returns (address) {
        return _fundManager();
    }

    function _relayer() internal view returns (address) {
        return IFund(fund).relayer();
    }

    function relayer() external view returns (address) {
        return _relayer();
    }

    function creator() external view override returns (address) {
        if (activeStrategy != ZERO_ADDRESS) {
            return IStrategy(activeStrategy).creator();
        }
        return deployer;
    }

    modifier onlyFund() {
        require(msg.sender == fund, "The sender has to be the fund");
        _;
    }

    modifier onlyFundManager() {
        require(
            msg.sender == _fundManager(),
            "The sender has to be the fund manager"
        );
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
     * @notice Allows Governance/Fund Manager to stop/start investing from this strategy to active strategies
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
     * It tries to withdraw from this optimizer contract if this has enough balance.
     * Otherwise, we withdraw from the active strategy.
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

        if (activeStrategy != ZERO_ADDRESS) {
            IStrategy(activeStrategy).withdrawToFund(
                underlyingAmount.sub(underlyingBalanceBefore)
            );
        }

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
     * @notice Withdraws all assets from the active strategy and transfers all underlying to fund.
     */
    function withdrawAllToFund() external override onlyFund {
        if (activeStrategy != ZERO_ADDRESS) {
            IStrategy(activeStrategy).withdrawAllToFund();
        }
        uint256 underlyingBalance = IERC20(underlying).balanceOf(address(this));
        if (underlyingBalance > 0) {
            IERC20(underlying).safeTransfer(fund, underlyingBalance);
        }
    }

    /**
     * @notice This selects new active strategy based on APR
     * @dev If active strategy is changed, funds are withdrawn from current active strategy
     */
    function _selectActiveStrategy() internal {
        if (strategies.length > 0) {
            uint256 highestApr = 0;
            address highestAprStrategy;

            uint256 underlyingBalance =
                IERC20(underlying).balanceOf(address(this));

            for (uint256 i = 0; i < strategies.length; i++) {
                uint256 apr;
                apr = IStrategyUnderOptimizer(strategies[i]).aprAfterDeposit(
                    underlyingBalance
                );
                if (apr > highestApr) {
                    highestApr = apr;
                    highestAprStrategy = strategies[i];
                }
            }

            if (highestAprStrategy != activeStrategy) {
                if (activeStrategy != ZERO_ADDRESS) {
                    IStrategy(activeStrategy).withdrawAllToFund();
                }
                activeStrategy = highestAprStrategy;
                emit ActiveStrategyChangedOptimizer(activeStrategy);
            }
        } else {
            if (activeStrategy != ZERO_ADDRESS) {
                activeStrategy = ZERO_ADDRESS;
                emit ActiveStrategyChangedOptimizer(activeStrategy);
            }
        }
    }

    /**
     * @notice Invests all underlying assets into active strategy
     */
    function _investAllUnderlying() internal {
        if (!investActivated) {
            return;
        }

        uint256 underlyingBalance = IERC20(underlying).balanceOf(address(this));

        if (activeStrategy != ZERO_ADDRESS) {
            if (underlyingBalance > 0) {
                // deposits the entire balance to active strategy
                IERC20(underlying).safeTransfer(
                    activeStrategy,
                    underlyingBalance
                );
            }
            IStrategy(activeStrategy).doHardWork();
        }
    }

    /**
     * @notice This selects new active strategy based on APR and invests all the underlying there.
     * @dev If active strategy is changed, funds are first withdrawn from current active strategy
     */
    function doHardWork() external override onlyFund {
        _selectActiveStrategy();
        _investAllUnderlying();
    }

    /**
     * @notice Adds a new strategy to select active strategy from.
     * @param newStrategy Strategy to add
     */
    function addStrategy(address newStrategy) external onlyFundManager {
        require(newStrategy != ZERO_ADDRESS, "newStrategy cannot be empty");
        // The strategies added in optimizer treat optimizer as fund.
        require(
            IStrategy(newStrategy).fund() == address(this),
            "The strategy does not belong to this optimizer"
        );
        for (uint256 i = 0; i < strategies.length; i++) {
            require(
                newStrategy != strategies[i],
                "The strategy is already added in this optimizer"
            );
        }

        strategies.push(newStrategy);

        emit StrategyAddedOptimizer(newStrategy);
    }

    /**
     * @notice Removes the strategy from the optimizer.
     * If it is an active strategy, funds are withdrawn from it, and reinvested in the newly selected active strategy.
     * @param strategy Strategy to remove
     */
    function removeStrategy(address strategy)
        external
        onlyFundManagerOrGovernance
    {
        require(strategy != ZERO_ADDRESS, "strategy cannot be empty");

        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategy == strategies[i]) {
                IStrategy(strategy).withdrawAllToFund();
                if (i != strategies.length - 1) {
                    strategies[i] = strategies[strategies.length - 1];
                }
                strategies.pop();
                if (strategy == activeStrategy) {
                    activeStrategy = ZERO_ADDRESS;
                    _selectActiveStrategy();
                }
                _investAllUnderlying();
                emit StrategyRemovedOptimizer(strategy);
                return;
            }
        }

        require(false, "This strategy is not part of this optimizer");
    }

    //we could make this more gas efficient but it is only used by a view function
    struct Strategy {
        string name;
        address strategy;
        uint256 investedUnderlyingBalance;
        uint256 apr;
    }

    /**
     * @notice Returns the details of all the strategies in the optimiser
     * @return Array of Strategy struct
     */
    function getStrategies() public view returns (Strategy[] memory) {
        Strategy[] memory _strategies = new Strategy[](strategies.length);
        for (uint256 i = 0; i < strategies.length; i++) {
            Strategy memory s;
            s.name = IStrategy(strategies[i]).name();
            s.strategy = strategies[i];
            s.investedUnderlyingBalance = IStrategy(strategies[i])
                .investedUnderlyingBalance();
            s.apr = IStrategyUnderOptimizer(strategies[i]).apr();
            _strategies[i] = s;
        }

        return _strategies;
    }

    /**
     * @notice No tokens apart from underlying asset should ever be stored on this contract.
     * Any tokens that are sent here by mistake are recoverable by owner.
     * @dev Not applicable for ETH, different function needs to be written
     * @param  _token  Token address that needs to be recovered
     * @param  _sweepTo  Address to which tokens are sent
     */
    function sweep(address _token, address _sweepTo) external {
        require(_governance() == msg.sender, "Not governance");
        require(!canNotSweep[_token], "Token is restricted");
        require(_sweepTo != address(0), "Can not sweep to zero address");
        IERC20(_token).safeTransfer(
            _sweepTo,
            IERC20(_token).balanceOf(address(this))
        );
    }

    /**
     * @notice Returns the underlying invested balance. This is the underlying amount based on active strategy,
     * plus the current balance of the underlying asset.
     * @return Total balance invested in the strategy
     */
    function investedUnderlyingBalance()
        external
        view
        override
        returns (uint256)
    {
        uint256 underlyingBalanceinActiveStrategy;

        if (activeStrategy != ZERO_ADDRESS) {
            underlyingBalanceinActiveStrategy = IStrategy(activeStrategy)
                .investedUnderlyingBalance();
        }

        return
            underlyingBalanceinActiveStrategy.add(
                IERC20(underlying).balanceOf(address(this))
            );
    }
}
