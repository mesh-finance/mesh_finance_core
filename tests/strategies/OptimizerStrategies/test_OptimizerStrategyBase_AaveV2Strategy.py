#!/usr/bin/python3

import pytest, brownie

strategy_weightage = 8000


@pytest.fixture
def optimizer_strat(OptimizerStrategyBase, fund_through_proxy_usdc, accounts):
    return OptimizerStrategyBase.deploy(fund_through_proxy_usdc, {'from': accounts[0]})

@pytest.fixture
def aavev2strat(AaveV2LendingStrategyMainnet, optimizer_strat, accounts):
    return AaveV2LendingStrategyMainnet.deploy(optimizer_strat, {'from': accounts[0]})

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_add_aave_strategy_to_optimizer(aavev2strat, optimizer_strat, accounts):
    tx = optimizer_strat.addStrategy(aavev2strat, {'from': accounts[1]})

    assert optimizer_strat.getStrategies()[0] == ["AaveV2LendingStrategyMainnet", aavev2strat, 0, aavev2strat.apr()]
    assert tx.events["StrategyAddedOptimizer"].values() == [aavev2strat]

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_add_same_strategy_to_optimizer(aavev2strat, optimizer_strat, accounts):
    tx = optimizer_strat.addStrategy(aavev2strat, {'from': accounts[1]})

    with brownie.reverts("The strategy is already added in this optimizer"):
        optimizer_strat.addStrategy(aavev2strat, {'from': accounts[1]})

@pytest.fixture
def fund_through_proxy_with_aave_strategy_and_deposit(fund_through_proxy_usdc, optimizer_strat, aavev2strat, accounts, usdc, test_usdc_account):
    tx = fund_through_proxy_usdc.addStrategy(optimizer_strat, strategy_weightage, 500, {'from': accounts[1]})
    tx = optimizer_strat.addStrategy(aavev2strat, {'from': accounts[1]})
    
    amount_to_deposit = 1000 * (10 ** usdc.decimals())
    usdc.approve(fund_through_proxy_usdc, amount_to_deposit, {'from': test_usdc_account})
    fund_through_proxy_usdc.deposit(amount_to_deposit, {'from': test_usdc_account})
    
    return fund_through_proxy_usdc

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_set_invest_activate_with_random_address(fund_through_proxy_with_aave_strategy_and_deposit, optimizer_strat, accounts):
    with brownie.reverts("The sender has to be the governance or fund manager"):
        optimizer_strat.setInvestActivated(False, {'from': accounts[7]})

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_fund_with_aave_strategy_hardwork_with_optimizer_invest_activate_false(fund_through_proxy_with_aave_strategy_and_deposit, optimizer_strat, aavev2strat, usdc, accounts, interface):
    deposited_amount = 1000 * (10 ** usdc.decimals())
    required_fund = fund_through_proxy_with_aave_strategy_and_deposit
    usdc_balance_in_aave_before = aavev2strat.investedUnderlyingBalance()
    usdc_balance_in_optimizer_before = interface.IERC20(usdc).balanceOf(optimizer_strat)
    optimizer_strat.setInvestActivated(False, {'from': accounts[1]})
    required_fund.doHardWork({'from': accounts[1]})
    usdc_balance_in_aave_after = aavev2strat.investedUnderlyingBalance()
    usdc_balance_in_optimizer_after = interface.IERC20(usdc).balanceOf(optimizer_strat)
    assert usdc_balance_in_aave_before == usdc_balance_in_aave_after == 0
    assert usdc_balance_in_optimizer_before == 0
    assert usdc_balance_in_optimizer_after == deposited_amount*strategy_weightage/10000


def test_deposit_and_hard_work_with_aave_strategy(fund_through_proxy_with_aave_strategy_and_deposit, optimizer_strat, aavev2strat, usdc, accounts):
    required_fund = fund_through_proxy_with_aave_strategy_and_deposit
    amount_deposited = 1000 * (10 ** usdc.decimals())
    tx = required_fund.doHardWork({'from': accounts[1]})

    assert optimizer_strat.activeStrategy() == aavev2strat
    assert tx.events["ActiveStrategyChangedOptimizer"].values() == [aavev2strat]
    assert optimizer_strat.investedUnderlyingBalance() == aavev2strat.investedUnderlyingBalance()
    assert float(aavev2strat.investedUnderlyingBalance()) == pytest.approx((strategy_weightage/10000 * amount_deposited))

@pytest.fixture
def fund_with_deposit_and_hard_work_with_aave_strategy(fund_through_proxy_with_aave_strategy_and_deposit, optimizer_strat, aavev2strat, usdc, accounts):
    required_fund = fund_through_proxy_with_aave_strategy_and_deposit
    required_fund.doHardWork({'from': accounts[1]})
    return required_fund

@pytest.fixture
def profitstrat_1_optimizer(ProfitStrategy, optimizer_strat, accounts):
    return ProfitStrategy.deploy(optimizer_strat, 100, {'from': accounts[5]})

def test_fund_with_aave_strategy_and_profit1_strategy_hardwork(fund_with_deposit_and_hard_work_with_aave_strategy, optimizer_strat, aavev2strat, profitstrat_1_optimizer, accounts):
    optimizer_strat.addStrategy(profitstrat_1_optimizer, {'from': accounts[1]})
    fund_with_deposit_and_hard_work_with_aave_strategy.doHardWork({'from':accounts[1]})
    assert optimizer_strat.getStrategies()[0] == ["AaveV2LendingStrategyMainnet", aavev2strat, aavev2strat.investedUnderlyingBalance(), aavev2strat.apr()]
    assert optimizer_strat.getStrategies()[1] == ["ProfitStrategy", profitstrat_1_optimizer, 0, 10000]
    assert optimizer_strat.activeStrategy() == aavev2strat
    assert optimizer_strat.investedUnderlyingBalance() == aavev2strat.investedUnderlyingBalance()

@pytest.fixture
def profitstrat_50_optimizer(ProfitStrategy, optimizer_strat, accounts):
    return ProfitStrategy.deploy(optimizer_strat, 5000, {'from': accounts[5]})

def test_fund_with_aave_strategy_and_profit50_strategy_hardwork(fund_with_deposit_and_hard_work_with_aave_strategy, optimizer_strat, aavev2strat, profitstrat_50_optimizer, accounts, usdc):
    deposited_amount = 1000 * (10 ** usdc.decimals())
    optimizer_strat.addStrategy(profitstrat_50_optimizer, {'from': accounts[1]})
    fund_with_deposit_and_hard_work_with_aave_strategy.doHardWork({'from':accounts[1]})
    assert optimizer_strat.getStrategies()[0] == ["AaveV2LendingStrategyMainnet", aavev2strat, 0, aavev2strat.apr()]
    assert optimizer_strat.getStrategies()[1][0] == "ProfitStrategy"
    assert float(optimizer_strat.getStrategies()[1][2]) == pytest.approx((deposited_amount*strategy_weightage)/10000)
    assert optimizer_strat.activeStrategy() == profitstrat_50_optimizer
    assert optimizer_strat.investedUnderlyingBalance() == profitstrat_50_optimizer.investedUnderlyingBalance()

@pytest.fixture
def fund_with_deposit_and_hard_work_with_aave_strategy_and_profit1_strategy_hardwork(fund_through_proxy_with_aave_strategy_and_deposit, optimizer_strat, aavev2strat, accounts, profitstrat_1_optimizer):
    optimizer_strat.addStrategy(profitstrat_1_optimizer, {'from': accounts[1]})
    required_fund = fund_through_proxy_with_aave_strategy_and_deposit
    required_fund.doHardWork({'from':accounts[1]})
    return required_fund

def test_withdraw_small(fund_with_deposit_and_hard_work_with_aave_strategy_and_profit1_strategy_hardwork, aavev2strat, usdc, test_usdc_account):    
    required_fund = fund_with_deposit_and_hard_work_with_aave_strategy_and_profit1_strategy_hardwork
    shares_to_withdraw = 100 * (10 ** required_fund.decimals())
    price_per_share = required_fund.getPricePerShare()
    amount_to_withdraw = shares_to_withdraw * price_per_share / (10 ** required_fund.decimals())

    fund_balance_before = required_fund.balanceOf(test_usdc_account)
    usdc_balance_before = usdc.balanceOf(test_usdc_account)
    token_in_fund_before = usdc.balanceOf(required_fund)
    strategy_balance_before = aavev2strat.investedUnderlyingBalance()

    required_fund.withdraw(shares_to_withdraw, {'from': test_usdc_account})

    fund_balance_after = required_fund.balanceOf(test_usdc_account)
    usdc_balance_after = usdc.balanceOf(test_usdc_account)
    token_in_fund_after = usdc.balanceOf(required_fund)
    strategy_balance_after = aavev2strat.investedUnderlyingBalance()

    assert fund_balance_before - fund_balance_after == shares_to_withdraw
    assert float(usdc_balance_after - usdc_balance_before) == pytest.approx(amount_to_withdraw)
    assert float(token_in_fund_before - token_in_fund_after) == pytest.approx(amount_to_withdraw)
    assert float(strategy_balance_after) == pytest.approx(strategy_balance_before)

def test_withdraw_large(fund_with_deposit_and_hard_work_with_aave_strategy_and_profit1_strategy_hardwork, aavev2strat, usdc, test_usdc_account):
    required_fund = fund_with_deposit_and_hard_work_with_aave_strategy_and_profit1_strategy_hardwork
    shares_to_withdraw = 600 * (10 ** required_fund.decimals())
    price_per_share = required_fund.getPricePerShare()
    amount_to_withdraw = required_fund.underlyingFromShares(shares_to_withdraw)

    fund_balance_before = required_fund.balanceOf(test_usdc_account)
    token_balance_before = usdc.balanceOf(test_usdc_account)
    token_in_fund_before = usdc.balanceOf(required_fund)
    strategy_balance_before = aavev2strat.investedUnderlyingBalance()

    required_fund.withdraw(shares_to_withdraw, {'from': test_usdc_account})

    fund_balance_after = required_fund.balanceOf(test_usdc_account)
    token_balance_after = usdc.balanceOf(test_usdc_account)
    token_in_fund_after = usdc.balanceOf(required_fund)
    strategy_balance_after = aavev2strat.investedUnderlyingBalance()

    assert fund_balance_before - fund_balance_after == shares_to_withdraw
    assert float(token_balance_after - token_balance_before) == pytest.approx(amount_to_withdraw)
    assert token_in_fund_after == 0
    assert float(strategy_balance_before - strategy_balance_after) == pytest.approx(amount_to_withdraw - token_in_fund_before)

def test_remove_strategies_from_optimizer(fund_with_deposit_and_hard_work_with_aave_strategy_and_profit1_strategy_hardwork, profitstrat_1_optimizer, aavev2strat, optimizer_strat, accounts, zero_account):
    
    assert optimizer_strat.activeStrategy() == aavev2strat
    assert optimizer_strat.getStrategies()[1][1] == profitstrat_1_optimizer
    strategy_balance_before = optimizer_strat.investedUnderlyingBalance()
    tx = optimizer_strat.removeStrategy(aavev2strat, {'from': accounts[1]})
    strategy_balance_after = optimizer_strat.investedUnderlyingBalance()
    
    assert optimizer_strat.activeStrategy() == profitstrat_1_optimizer
    assert tx.events["ActiveStrategyChangedOptimizer"].values() == [profitstrat_1_optimizer]
    assert float(strategy_balance_after) == pytest.approx(strategy_balance_before)
    assert tx.events["StrategyRemovedOptimizer"].values() == [aavev2strat]

    tx = optimizer_strat.removeStrategy(profitstrat_1_optimizer, {'from': accounts[1]})

    strategy_balance_after = optimizer_strat.investedUnderlyingBalance()

    assert optimizer_strat.activeStrategy() == zero_account
    # assert tx.events["ActiveStrategyChangedOptimizer"].values() == [zero_account]
    assert float(strategy_balance_after) == pytest.approx(strategy_balance_before)
    assert tx.events["StrategyRemovedOptimizer"].values() == [profitstrat_1_optimizer]

def test_remove_strategy_from_fund(fund_with_deposit_and_hard_work_with_aave_strategy_and_profit1_strategy_hardwork, optimizer_strat, usdc, accounts):

    required_fund = fund_with_deposit_and_hard_work_with_aave_strategy_and_profit1_strategy_hardwork

    total_value_locked_before = required_fund.totalValueLocked()
    strategy_balance_before = optimizer_strat.investedUnderlyingBalance()

    tx = required_fund.removeStrategy(optimizer_strat, {'from': accounts[0]})

    total_value_locked_after = required_fund.totalValueLocked()
    strategy_balance_after = optimizer_strat.investedUnderlyingBalance()

    assert required_fund.getStrategyList() == []
    assert tx.events["StrategyRemoved"].values() == [optimizer_strat]
    assert float(total_value_locked_before) == pytest.approx(total_value_locked_after)
    assert strategy_balance_after == 0