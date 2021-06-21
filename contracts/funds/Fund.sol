// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

pragma experimental ABIEncoderV2;

import "OpenZeppelin/openzeppelin-contracts-upgradeable@3.4.0/contracts/utils/AddressUpgradeable.sol";
import "OpenZeppelin/openzeppelin-contracts-upgradeable@3.4.0/contracts/math/MathUpgradeable.sol";
import "OpenZeppelin/openzeppelin-contracts-upgradeable@3.4.0/contracts/math/SafeMathUpgradeable.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/IERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/SafeERC20.sol";
import "OpenZeppelin/openzeppelin-contracts-upgradeable@3.4.0/contracts/token/ERC20/ERC20Upgradeable.sol";
import "OpenZeppelin/openzeppelin-contracts-upgradeable@3.4.0/contracts/utils/ReentrancyGuardUpgradeable.sol";
import "../../interfaces/IFund.sol";
import "../../interfaces/IUpgradeSource.sol";
import "../../interfaces/IStrategy.sol";
import "../utils/Governable.sol";
import "./FundStorage.sol";

contract Fund is
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable,
    IFund,
    IUpgradeSource,
    Governable,
    FundStorage
{
    using SafeERC20 for IERC20;
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;
    using SafeMathUpgradeable for uint8;

    event Withdraw(address indexed beneficiary, uint256 amount, uint256 fee);
    event Deposit(address indexed beneficiary, uint256 amount);
    event InvestInStrategy(address strategy, uint256 amount);
    event StrategyRewards(
        address strategy,
        uint256 profit,
        uint256 strategyCreatorFee
    );
    event FundManagerRewards(uint256 profitTotal, uint256 fundManagerFee);
    event PlatformRewards(
        uint256 lastBalance,
        uint256 timeElapsed,
        uint256 platformFee
    );
    event HardWorkDone(uint256 totalValueLocked, uint256 pricePerShare);

    event StrategyAdded(
        address strategy,
        uint256 weightage,
        uint256 performanceFeeStrategy
    );
    event StrategyWeightageUpdated(address strategy, uint256 newWeightage);
    event StrategyPerformanceFeeUpdated(
        address strategy,
        uint256 newPerformanceFeeStrategy
    );
    event StrategyRemoved(address strategy);

    address internal constant ZERO_ADDRESS = address(0);

    uint256 internal constant MAX_BPS = 10000; // 100% in basis points
    uint256 internal constant SECS_PER_YEAR = 31556952; // 365.25 days from yearn

    uint256 internal constant MAX_PLATFORM_FEE = 500; // 5% (annual on AUM), goes to governance/treasury
    uint256 internal constant MAX_PERFORMANCE_FEE_FUND = 1000; // 10% on profits, goes to fund manager
    uint256 internal constant MAX_PERFORMANCE_FEE_STRATEGY = 1000; // 10% on profits, goes to strategy creator
    uint256 internal constant MAX_WITHDRAWAL_FEE = 100; // 1%, goes to governance/treasury

    struct StrategyParams {
        uint256 weightage; // weightage of total assets in fund this strategy can access (in BPS) (5000 for 50%)
        uint256 performanceFeeStrategy; // in BPS, fee on yield of the strategy, goes to strategy creator
        uint256 activation; // timestamp when strategy is added
        uint256 lastBalance; // balance at last hard work
        uint256 indexInList;
    }

    mapping(address => StrategyParams) public strategies;
    address[] public strategyList;

    // solhint-disable-next-line no-empty-blocks
    constructor() public {}

    function initializeFund(
        address _governance,
        address _underlying,
        string memory _name,
        string memory _symbol
    ) public initializer {
        ERC20Upgradeable.__ERC20_init(_name, _symbol);

        __ReentrancyGuard_init();

        Governable.initializeGovernance(_governance);

        uint8 _decimals = ERC20Upgradeable(_underlying).decimals();

        uint256 _underlyingUnit = 10**uint256(_decimals);

        FundStorage.initializeFundStorage(
            _underlying,
            _underlyingUnit,
            _decimals,
            _governance, // fund manager is initialized as governance
            _governance, // relayer is initialized as governance
            _governance // rewards contract is initialized as governance
        );
    }

    modifier onlyFundManagerOrGovernance() {
        require(
            (_governance() == msg.sender) || (_fundManager() == msg.sender),
            "Not governance nor fund manager"
        );
        _;
    }

    modifier onlyFundManagerOrGovernanceOrRelayer() {
        require(
            (_governance() == msg.sender) ||
                (_fundManager() == msg.sender) ||
                (_relayer() == msg.sender),
            "Not governance nor fund manager nor relayer"
        );
        _;
    }

    modifier whenDepositsNotPaused() {
        require(!_depositsPaused(), "Deposits are paused");
        _;
    }

    function fundManager() external view returns (address) {
        return _fundManager();
    }

    function relayer() external view override returns (address) {
        return _relayer();
    }

    function underlying() external view override returns (address) {
        return _underlying();
    }

    function underlyingUnit() external view returns (uint256) {
        return _underlyingUnit();
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals();
    }

    function getStrategyCount() internal view returns (uint256) {
        return strategyList.length;
    }

    modifier whenStrategyDefined() {
        require(getStrategyCount() > 0, "Strategies must be defined");
        _;
    }

    function getStrategyList() public view returns (address[] memory) {
        return strategyList;
    }

    function getStrategy(address strategy)
        public
        view
        returns (StrategyParams memory)
    {
        return strategies[strategy];
    }

    /*
     * Returns the underlying balance currently in the fund.
     */
    function underlyingBalanceInFund() internal view returns (uint256) {
        return IERC20(_underlying()).balanceOf(address(this));
    }

    /*
     * Returns the current underlying (e.g., DAI's) balance together with
     * the invested amount (if DAI is invested elsewhere by the strategies).
     */
    function underlyingBalanceWithInvestment() internal view returns (uint256) {
        uint256 underlyingBalance = underlyingBalanceInFund();
        for (uint256 i; i < getStrategyCount(); i++) {
            underlyingBalance = underlyingBalance.add(
                IStrategy(strategyList[i]).investedUnderlyingBalance()
            );
        }
        return underlyingBalance;
    }

    /*
     * Returns price per share, scaled by underlying unit (10 ** decimals) to keep everything in uint256.
     */
    function _getPricePerShare() internal view returns (uint256) {
        return
            totalSupply() == 0
                ? _underlyingUnit()
                : _underlyingUnit().mul(underlyingBalanceWithInvestment()).div(
                    totalSupply()
                );
    }

    function getPricePerShare() external view override returns (uint256) {
        return _getPricePerShare();
    }

    function totalValueLocked() external view override returns (uint256) {
        return underlyingBalanceWithInvestment();
    }

    function _underlyingFromShares(uint256 numShares)
        internal
        view
        returns (uint256)
    {
        return
            underlyingBalanceWithInvestment().mul(numShares).div(totalSupply());
    }

    /*
     * get the user's balance (in underlying)
     */
    function underlyingBalanceWithInvestmentForHolder(address holder)
        external
        view
        override
        returns (uint256)
    {
        if (totalSupply() == 0) {
            return 0;
        }
        return _underlyingFromShares(balanceOf(holder));
    }

    function isActiveStrategy(address strategy) internal view returns (bool) {
        return strategies[strategy].weightage > 0;
    }

    function addStrategy(
        address newStrategy,
        uint256 weightage,
        uint256 performanceFeeStrategy
    ) external onlyFundManagerOrGovernance {
        require(newStrategy != ZERO_ADDRESS, "new newStrategy cannot be empty");
        require(
            IStrategy(newStrategy).fund() == address(this),
            "The strategy does not belong to this fund"
        );
        require(
            isActiveStrategy(newStrategy) == false,
            "This strategy is already active in this fund"
        );
        require(weightage > 0, "The weightage should be greater than 0");
        uint256 totalWeightInStrategies =
            _totalWeightInStrategies().add(weightage);
        require(
            totalWeightInStrategies <= _maxInvestmentInStrategies(),
            "Total investment can't be above max allowed"
        );
        require(
            performanceFeeStrategy <= MAX_PERFORMANCE_FEE_STRATEGY,
            "Performance fee too high"
        );

        strategies[newStrategy].weightage = weightage;
        _setTotalWeightInStrategies(totalWeightInStrategies);
        // solhint-disable-next-line not-rely-on-time
        strategies[newStrategy].activation = block.timestamp;
        strategies[newStrategy].indexInList = getStrategyCount();
        strategies[newStrategy].performanceFeeStrategy = performanceFeeStrategy;
        strategyList.push(newStrategy);
        _setShouldRebalance(true);

        IERC20(_underlying()).safeApprove(newStrategy, 0);
        IERC20(_underlying()).safeApprove(newStrategy, type(uint256).max);

        emit StrategyAdded(newStrategy, weightage, performanceFeeStrategy);
    }

    function removeStrategy(address activeStrategy)
        external
        onlyFundManagerOrGovernance
    {
        require(
            activeStrategy != ZERO_ADDRESS,
            "current strategy cannot be empty"
        );
        require(
            isActiveStrategy(activeStrategy),
            "This strategy is not active in this fund"
        );

        _setTotalWeightInStrategies(
            _totalWeightInStrategies().sub(strategies[activeStrategy].weightage)
        );
        uint256 totalStrategies = getStrategyCount();
        for (
            uint256 i = strategies[activeStrategy].indexInList;
            i < totalStrategies - 1;
            i++
        ) {
            strategyList[i] = strategyList[i + 1];
            strategies[strategyList[i]].indexInList = i;
        }
        strategyList.pop();
        delete strategies[activeStrategy];
        IERC20(_underlying()).safeApprove(activeStrategy, 0);
        IStrategy(activeStrategy).withdrawAllToFund();
        _setShouldRebalance(true);

        emit StrategyRemoved(activeStrategy);
    }

    function updateStrategyWeightage(
        address activeStrategy,
        uint256 newWeightage
    ) external onlyFundManagerOrGovernance {
        require(
            activeStrategy != ZERO_ADDRESS,
            "current strategy cannot be empty"
        );
        require(
            isActiveStrategy(activeStrategy),
            "This strategy is not active in this fund"
        );
        require(newWeightage > 0, "The weightage should be greater than 0");
        uint256 totalWeightInStrategies =
            _totalWeightInStrategies()
                .sub(strategies[activeStrategy].weightage)
                .add(newWeightage);
        require(
            totalWeightInStrategies <= _maxInvestmentInStrategies(),
            "Total investment can't be above max allowed"
        );

        _setTotalWeightInStrategies(totalWeightInStrategies);
        strategies[activeStrategy].weightage = newWeightage;
        _setShouldRebalance(true);

        emit StrategyWeightageUpdated(activeStrategy, newWeightage);
    }

    function updateStrategyPerformanceFee(
        address activeStrategy,
        uint256 newPerformanceFeeStrategy
    ) external onlyFundManagerOrGovernance {
        require(
            activeStrategy != ZERO_ADDRESS,
            "current strategy cannot be empty"
        );
        require(
            isActiveStrategy(activeStrategy),
            "This strategy is not active in this fund"
        );
        require(
            newPerformanceFeeStrategy <= MAX_PERFORMANCE_FEE_STRATEGY,
            "Performance fee too high"
        );

        strategies[activeStrategy]
            .performanceFeeStrategy = newPerformanceFeeStrategy;

        emit StrategyPerformanceFeeUpdated(
            activeStrategy,
            newPerformanceFeeStrategy
        );
    }

    function processFees() internal {
        uint256 profitToFund = 0;

        for (uint256 i; i < getStrategyCount(); i++) {
            address strategy = strategyList[i];

            uint256 profit = 0;
            uint256 strategyCreatorFee = 0;

            if (
                IStrategy(strategy).investedUnderlyingBalance() >
                strategies[strategy].lastBalance
            ) {
                profit =
                    IStrategy(strategy).investedUnderlyingBalance() -
                    strategies[strategy].lastBalance;
                strategyCreatorFee = profit
                    .mul(strategies[strategy].performanceFeeStrategy)
                    .div(MAX_BPS);
                if (
                    strategyCreatorFee > 0 &&
                    strategyCreatorFee < underlyingBalanceInFund()
                ) {
                    IERC20(_underlying()).safeTransfer(
                        IStrategy(strategy).creator(),
                        strategyCreatorFee
                    );
                }
                profitToFund = profitToFund.add(profit).sub(strategyCreatorFee);
            }
            emit StrategyRewards(strategy, profit, strategyCreatorFee);
        }

        uint256 fundManagerFee =
            profitToFund.mul(_performanceFeeFund()).div(MAX_BPS);
        if (fundManagerFee > 0 && fundManagerFee < underlyingBalanceInFund()) {
            address fundManagerRewards =
                (_fundManager() == _governance())
                    ? _platformRewards()
                    : _fundManager();
            IERC20(_underlying()).safeTransfer(
                fundManagerRewards,
                fundManagerFee
            );
            emit FundManagerRewards(profitToFund, fundManagerFee);
        }

        uint256 platformFee =
            // solhint-disable-next-line not-rely-on-time
            (_totalInvested() * (block.timestamp - _lastHardworkTimestamp()))
                .mul(_platformFee())
                .div(MAX_BPS)
                .div(SECS_PER_YEAR);

        if (platformFee > 0 && platformFee < underlyingBalanceInFund()) {
            IERC20(_underlying()).safeTransfer(_platformRewards(), platformFee);
            emit PlatformRewards(
                _totalInvested(),
                // solhint-disable-next-line not-rely-on-time
                block.timestamp - _lastHardworkTimestamp(),
                platformFee
            );
        }
    }

    /*
     * Invests the underlying capital to various strategies. Looks for weightage changes.
     */
    function doHardWork()
        external
        whenStrategyDefined
        onlyFundManagerOrGovernanceOrRelayer
    {
        if (_lastHardworkTimestamp() > 0) {
            processFees();
        }
        // ensure that new funds are invested too

        if (_shouldRebalance()) {
            _setShouldRebalance(false);
            doHardWorkWithRebalance();
        } else {
            doHardWorkWithoutRebalance();
        }
        // solhint-disable-next-line not-rely-on-time
        _setLastHardworkTimestamp(block.timestamp);
        emit HardWorkDone(
            underlyingBalanceWithInvestment(),
            _getPricePerShare()
        );
    }

    function doHardWorkWithoutRebalance() internal {
        uint256 lastReserve =
            _totalAccounted() > 0 ? _totalAccounted().sub(_totalInvested()) : 0;
        uint256 availableAmountToInvest =
            underlyingBalanceInFund() > lastReserve
                ? underlyingBalanceInFund().sub(lastReserve)
                : 0;

        if (availableAmountToInvest == 0) {
            return;
        }

        _setTotalAccounted(_totalAccounted().add(availableAmountToInvest));
        uint256 totalInvested = 0;

        for (uint256 i; i < getStrategyCount(); i++) {
            address strategy = strategyList[i];
            uint256 availableAmountForStrategy =
                availableAmountToInvest.mul(strategies[strategy].weightage).div(
                    MAX_BPS
                );
            if (availableAmountForStrategy > 0) {
                IERC20(_underlying()).safeTransfer(
                    strategy,
                    availableAmountForStrategy
                );
                totalInvested = totalInvested.add(availableAmountForStrategy);
                emit InvestInStrategy(strategy, availableAmountForStrategy);
            }

            IStrategy(strategy).doHardWork();

            strategies[strategy].lastBalance = IStrategy(strategy)
                .investedUnderlyingBalance();
        }
        _setTotalInvested(totalInvested);
    }

    function doHardWorkWithRebalance() internal {
        uint256 totalUnderlyingWithInvestment =
            underlyingBalanceWithInvestment();
        _setTotalAccounted(totalUnderlyingWithInvestment);
        uint256 totalInvested = 0;
        uint256[] memory toDeposit = new uint256[](getStrategyCount());

        for (uint256 i; i < getStrategyCount(); i++) {
            address strategy = strategyList[i];
            uint256 shouldBeInStrategy =
                totalUnderlyingWithInvestment
                    .mul(strategies[strategy].weightage)
                    .div(MAX_BPS);
            totalInvested = totalInvested.add(shouldBeInStrategy);
            uint256 currentlyInStrategy =
                IStrategy(strategy).investedUnderlyingBalance();
            if (currentlyInStrategy > shouldBeInStrategy) {
                // withdraw from strategy
                IStrategy(strategy).withdrawToFund(
                    currentlyInStrategy.sub(shouldBeInStrategy)
                );
            } else if (shouldBeInStrategy > currentlyInStrategy) {
                // can not directly deposit here as there might not be enough balance before withdrawing from required strategies
                toDeposit[i] = shouldBeInStrategy.sub(currentlyInStrategy);
            }
        }
        _setTotalInvested(totalInvested);

        for (uint256 i; i < getStrategyCount(); i++) {
            address strategy = strategyList[i];
            if (toDeposit[i] > 0) {
                IERC20(_underlying()).safeTransfer(strategy, toDeposit[i]);
                emit InvestInStrategy(strategy, toDeposit[i]);
            }
            IStrategy(strategy).doHardWork();

            strategies[strategy].lastBalance = IStrategy(strategy)
                .investedUnderlyingBalance();
        }
    }

    function pauseDeposits(bool trigger) external onlyFundManagerOrGovernance {
        _setDepositsPaused(trigger);
    }

    /*
     * Allows for depositing the underlying asset in exchange for shares.
     * Approval is assumed.
     */
    function deposit(uint256 amount)
        external
        override
        nonReentrant
        whenDepositsNotPaused
    {
        _deposit(amount, msg.sender, msg.sender);
    }

    /*
     * Allows for depositing the underlying asset and shares assigned to the holder.
     * This facilitates depositing for someone else (e.g. using DepositHelper)
     */
    function depositFor(uint256 amount, address holder)
        external
        override
        nonReentrant
        whenDepositsNotPaused
    {
        require(holder != ZERO_ADDRESS, "holder must be defined");
        _deposit(amount, msg.sender, holder);
    }

    function _deposit(
        uint256 amount,
        address sender,
        address beneficiary
    ) internal {
        require(amount > 0, "Cannot deposit 0");

        if (_depositLimit() > 0) {
            // if deposit limit is 0, then there is no deposit limit
            require(
                underlyingBalanceWithInvestment().add(amount) <=
                    _depositLimit(),
                "Total deposit limit hit"
            );
        }

        if (_depositLimitTxMax() > 0) {
            // if deposit limit is 0, then there is no deposit limit
            require(
                amount <= _depositLimitTxMax(),
                "Maximum transaction deposit limit hit"
            );
        }

        if (_depositLimitTxMin() > 0) {
            // if deposit limit is 0, then there is no deposit limit
            require(
                amount >= _depositLimitTxMin(),
                "Minimum transaction deposit limit hit"
            );
        }

        uint256 toMint =
            totalSupply() == 0
                ? amount
                : amount.mul(totalSupply()).div(
                    underlyingBalanceWithInvestment()
                );
        _mint(beneficiary, toMint);

        IERC20(_underlying()).safeTransferFrom(sender, address(this), amount);
        emit Deposit(beneficiary, amount);
    }

    function withdraw(uint256 numberOfShares) external override nonReentrant {
        require(totalSupply() > 0, "Fund has no shares");
        require(numberOfShares > 0, "numberOfShares must be greater than 0");

        uint256 underlyingAmountToWithdraw =
            _underlyingFromShares(numberOfShares);
        _burn(msg.sender, numberOfShares);

        if (underlyingAmountToWithdraw > underlyingBalanceInFund()) {
            uint256 missing =
                underlyingAmountToWithdraw.sub(underlyingBalanceInFund());
            uint256 missingCarryOver;
            for (uint256 i; i < getStrategyCount(); i++) {
                if (isActiveStrategy(strategyList[i])) {
                    uint256 balanceBefore = underlyingBalanceInFund();
                    uint256 weightage = strategies[strategyList[i]].weightage;
                    uint256 missingforStrategy =
                        (missing.mul(weightage).div(_totalWeightInStrategies()))
                            .add(missingCarryOver);
                    IStrategy(strategyList[i]).withdrawToFund(
                        missingforStrategy
                    );
                    missingCarryOver = missingforStrategy
                        .add(balanceBefore)
                        .sub(underlyingBalanceInFund());
                }
            }
            // recalculate to improve accuracy
            underlyingAmountToWithdraw = MathUpgradeable.min(
                underlyingAmountToWithdraw,
                underlyingBalanceInFund()
            );
            _setShouldRebalance(true);
        }

        uint256 withdrawalFee =
            underlyingAmountToWithdraw.mul(_withdrawalFee()).div(MAX_BPS);

        if (withdrawalFee > 0) {
            IERC20(_underlying()).safeTransfer(
                _platformRewards(),
                withdrawalFee
            );
            underlyingAmountToWithdraw = underlyingAmountToWithdraw.sub(
                withdrawalFee
            );
        }

        IERC20(_underlying()).safeTransfer(
            msg.sender,
            underlyingAmountToWithdraw
        );

        emit Withdraw(msg.sender, underlyingAmountToWithdraw, withdrawalFee);
    }

    /**
     * Schedules an upgrade for this fund's proxy.
     */
    function scheduleUpgrade(address newImplementation)
        external
        onlyGovernance
    {
        // Timelock implementation can be done here later
        _setNextImplementation(newImplementation);
    }

    function shouldUpgrade() external view override returns (bool, address) {
        return (_nextImplementation() != address(0), _nextImplementation());
    }

    function finalizeUpgrade() external override onlyGovernance {
        _setNextImplementation(address(0));
    }

    function setFundManager(address newFundManager)
        external
        onlyFundManagerOrGovernance
    {
        _setFundManager(newFundManager);
    }

    function setRelayer(address newRelayer)
        external
        onlyFundManagerOrGovernance
    {
        _setRelayer(newRelayer);
    }

    function setPlatformRewards(address newRewards) external onlyGovernance {
        _setPlatformRewards(newRewards);
    }

    function setShouldRebalance(bool trigger)
        external
        onlyFundManagerOrGovernance
    {
        _setShouldRebalance(trigger);
    }

    function setMaxInvestmentInStrategies(uint256 value)
        external
        onlyFundManagerOrGovernance
    {
        require(value < MAX_BPS, "Value greater than 100%");
        _setMaxInvestmentInStrategies(value);
    }

    // if limit == 0 then there is no deposit limit
    function setDepositLimit(uint256 limit)
        external
        onlyFundManagerOrGovernance
    {
        _setDepositLimit(limit);
    }

    function depositLimit() external view returns (uint256) {
        return _depositLimit();
    }

    // if limit == 0 then there is no deposit limit
    function setDepositLimitTxMax(uint256 limit)
        external
        onlyFundManagerOrGovernance
    {
        _setDepositLimitTxMax(limit);
    }

    function depositLimitTxMax() external view returns (uint256) {
        return _depositLimitTxMax();
    }

    // if limit == 0 then there is no deposit limit
    function setDepositLimitTxMin(uint256 limit)
        external
        onlyFundManagerOrGovernance
    {
        _setDepositLimitTxMin(limit);
    }

    function depositLimitTxMin() external view returns (uint256) {
        return _depositLimitTxMin();
    }

    function setPerformanceFeeFund(uint256 fee)
        external
        onlyFundManagerOrGovernance
    {
        require(fee <= MAX_PERFORMANCE_FEE_FUND, "Fee greater than max limit");
        _setPerformanceFeeFund(fee);
    }

    function performanceFeeFund() external view returns (uint256) {
        return _performanceFeeFund();
    }

    function setPlatformFee(uint256 fee) external onlyFundManagerOrGovernance {
        require(fee <= MAX_PLATFORM_FEE, "Fee greater than max limit");
        _setPlatformFee(fee);
    }

    function platformFee() external view returns (uint256) {
        return _platformFee();
    }

    function setWithdrawalFee(uint256 fee)
        external
        onlyFundManagerOrGovernance
    {
        require(fee <= MAX_WITHDRAWAL_FEE, "Fee greater than max limit");
        _setWithdrawalFee(fee);
    }

    function withdrawalFee() external view returns (uint256) {
        return _withdrawalFee();
    }

    // no tokens should ever be stored on this contract. Any tokens that are sent here by mistake are recoverable by governance
    function sweep(address _token, address _sweepTo) external onlyGovernance {
        require(_token != address(_underlying()), "can not sweep underlying");
        IERC20(_token).safeTransfer(
            _sweepTo,
            IERC20(_token).balanceOf(address(this))
        );
    }
}
