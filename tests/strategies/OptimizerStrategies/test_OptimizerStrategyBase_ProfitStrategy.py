#!/usr/bin/python3

import pytest, brownie

strategy_weightage = 8000

def test_deployment(OptimizerStrategyBase, fund_through_proxy, token, accounts):
    optimizer_strat = OptimizerStrategyBase.deploy(fund_through_proxy, {'from': accounts[0]})
    assert optimizer_strat.fund() == fund_through_proxy
    assert optimizer_strat.underlying() == token
    assert optimizer_strat.deployer() == accounts[0]
    assert optimizer_strat.creator() == accounts[0]  ## Since no active strategy

@pytest.fixture
def optimizer_strat(OptimizerStrategyBase, fund_through_proxy, accounts):
    return OptimizerStrategyBase.deploy(fund_through_proxy, {'from': accounts[0]})


def test_add_strategy_to_fund(optimizer_strat, fund_through_proxy, accounts):
    tx = fund_through_proxy.addStrategy(optimizer_strat, strategy_weightage, 500, {'from': accounts[1]})

    assert fund_through_proxy.getStrategyList() == [optimizer_strat]
    assert fund_through_proxy.getStrategy(optimizer_strat)[0] == strategy_weightage
    assert fund_through_proxy.getStrategy(optimizer_strat)[1] == 500
    assert tx.events["StrategyAdded"].values() == [optimizer_strat, strategy_weightage, 500]

@pytest.fixture
def profitstrat_10_optimizer(ProfitStrategy, optimizer_strat, accounts):
    return ProfitStrategy.deploy(optimizer_strat, 1000, {'from': accounts[0]})

def test_add_zero_strategy_to_optimizer(optimizer_strat, zero_account, accounts):

    with brownie.reverts("newStrategy cannot be empty"):
        optimizer_strat.addStrategy(zero_account, {'from': accounts[1]})

def test_add_random_strategy_to_optimizer(optimizer_strat, profit_strategy_10, accounts):

    with brownie.reverts("The strategy does not belong to this optimizer"):
        optimizer_strat.addStrategy(profit_strategy_10, {'from': accounts[1]})

def test_add_strategy_to_optimizer(profitstrat_10_optimizer, optimizer_strat, accounts):
    tx = optimizer_strat.addStrategy(profitstrat_10_optimizer, {'from': accounts[1]})

    assert optimizer_strat.getStrategies()[0] == ["ProfitStrategy", profitstrat_10_optimizer, 0, 100000]
    assert tx.events["StrategyAddedOptimizer"].values() == [profitstrat_10_optimizer]

def test_add_same_strategy_to_optimizer(profitstrat_10_optimizer, optimizer_strat, accounts):
    tx = optimizer_strat.addStrategy(profitstrat_10_optimizer, {'from': accounts[1]})

    with brownie.reverts("The strategy is already added in this optimizer"):
        optimizer_strat.addStrategy(profitstrat_10_optimizer, {'from': accounts[1]})

@pytest.fixture
def fund_through_proxy_with_strategy_and_deposit(fund_through_proxy, optimizer_strat, profitstrat_10_optimizer, token, accounts):
    token.grantRole(brownie.web3.keccak(text="MINTER_ROLE"), profitstrat_10_optimizer, {'from': accounts[0]})
    tx = fund_through_proxy.addStrategy(optimizer_strat, strategy_weightage, 500, {'from': accounts[1]})
    tx = optimizer_strat.addStrategy(profitstrat_10_optimizer, {'from': accounts[1]})
    
    amount_to_deposit = 1000 * (10 ** token.decimals())
    token.mint(accounts[3], amount_to_deposit, {'from': accounts[0]})
    token.approve(fund_through_proxy, amount_to_deposit, {'from': accounts[3]})
    fund_through_proxy.deposit(amount_to_deposit, {'from': accounts[3]})
    
    return fund_through_proxy

def test_hard_work_single_strategy(fund_through_proxy_with_strategy_and_deposit, optimizer_strat, profitstrat_10_optimizer, token, accounts):

    required_fund = fund_through_proxy_with_strategy_and_deposit
    amount_deposited = 1000 * (10 ** token.decimals())
    tx = required_fund.doHardWork({'from': accounts[1]})

    assert optimizer_strat.activeStrategy() == profitstrat_10_optimizer
    assert tx.events["ActiveStrategyChangedOptimizer"].values() == [profitstrat_10_optimizer]
    
    profitstrat_10_optimizer.investAllUnderlying({'from': accounts[0]})

    assert optimizer_strat.investedUnderlyingBalance() == profitstrat_10_optimizer.investedUnderlyingBalance()
    assert float(profitstrat_10_optimizer.investedUnderlyingBalance()) == pytest.approx((strategy_weightage/10000 * amount_deposited) * (1 + 1000/10000))
    assert float(required_fund.getPricePerShare()) == pytest.approx(required_fund.underlyingUnit() * (((strategy_weightage/10000 * amount_deposited) * (1 + 1000/10000)) + ((10000 - strategy_weightage)/10000 * amount_deposited)) / amount_deposited)
    # assert tx.events["StrategyRewards"].values() == [profit_strategy_10, 0, 0]  ## zero profit for first hard work

    amount_to_deposit = 1000 * (10 ** token.decimals())
    token.mint(accounts[3], amount_to_deposit, {'from': accounts[0]})
    token.approve(required_fund, amount_to_deposit, {'from': accounts[3]})
    required_fund.deposit(amount_to_deposit, {'from': accounts[3]})

    price_per_share = required_fund.getPricePerShare() / (10 ** required_fund.decimals())
    
    tx = required_fund.doHardWork({'from': accounts[1]})
    expected_profit = (strategy_weightage/10000 * amount_to_deposit) * (1000/10000)
    expected_strategy_creator_fee = expected_profit * (500/10000) / price_per_share
    assert tx.events["StrategyRewards"].values()[0] == optimizer_strat
    assert tx.events["StrategyRewards"].values()[1] == expected_profit
    assert float(tx.events["StrategyRewards"].values()[2]) == pytest.approx(expected_strategy_creator_fee)
    assert float(required_fund.balanceOf(accounts[0])) == pytest.approx(expected_strategy_creator_fee)

@pytest.fixture
def fund_through_proxy_with_strategy_and_deposit_after_hardwork(fund_through_proxy_with_strategy_and_deposit, profitstrat_10_optimizer, accounts):
    
    tx = fund_through_proxy_with_strategy_and_deposit.doHardWork({'from': accounts[1]})
    profitstrat_10_optimizer.investAllUnderlying({'from': accounts[0]})
    
    return fund_through_proxy_with_strategy_and_deposit

@pytest.fixture
def profitstrat_50_optimizer(ProfitStrategy, optimizer_strat, accounts):
    return ProfitStrategy.deploy(optimizer_strat, 5000, {'from': accounts[5]})

def test_add_2_strategy_to_optimizer(fund_through_proxy_with_strategy_and_deposit_after_hardwork, profitstrat_50_optimizer, optimizer_strat, accounts):
    tx = optimizer_strat.addStrategy(profitstrat_50_optimizer, {'from': accounts[1]})

    assert optimizer_strat.getStrategies()[1] == ["ProfitStrategy", profitstrat_50_optimizer, 0, 500000]
    assert tx.events["StrategyAddedOptimizer"].values() == [profitstrat_50_optimizer]

@pytest.fixture
def fund_through_proxy_with_2_strategies_deposit_and_hardwork(fund_through_proxy_with_strategy_and_deposit_after_hardwork, optimizer_strat, profitstrat_50_optimizer, token, accounts):
    token.grantRole(brownie.web3.keccak(text="MINTER_ROLE"), profitstrat_50_optimizer, {'from': accounts[0]})
    tx = optimizer_strat.addStrategy(profitstrat_50_optimizer, {'from': accounts[1]})
    
    return fund_through_proxy_with_strategy_and_deposit_after_hardwork

def test_hard_work_2_strategies_updated_active_strategy(fund_through_proxy_with_2_strategies_deposit_and_hardwork, optimizer_strat, profitstrat_10_optimizer, profitstrat_50_optimizer, token, accounts):

    required_fund = fund_through_proxy_with_2_strategies_deposit_and_hardwork
    amount_deposited = 1000 * (10 ** token.decimals())
    amount_in_strategy = optimizer_strat.investedUnderlyingBalance()

    price_per_share = required_fund.getPricePerShare() / (10 ** required_fund.decimals())
    expected_profit = (strategy_weightage/10000 * amount_deposited) * (1000/10000)
    expected_strategy_creator_fee = expected_profit * (500/10000) / price_per_share

    assert optimizer_strat.activeStrategy() == profitstrat_10_optimizer
    
    tx = required_fund.doHardWork({'from': accounts[1]})

    profitstrat_50_optimizer.investAllUnderlying({'from': accounts[0]})

    assert optimizer_strat.activeStrategy() == profitstrat_50_optimizer

    assert tx.events["ActiveStrategyChangedOptimizer"].values() == [profitstrat_50_optimizer]

    assert optimizer_strat.investedUnderlyingBalance() == profitstrat_50_optimizer.investedUnderlyingBalance()
    assert float(profitstrat_50_optimizer.investedUnderlyingBalance()) == pytest.approx((amount_in_strategy) * (1 + 5000/10000))
    assert tx.events["StrategyRewards"].values()[0] == optimizer_strat
    assert tx.events["StrategyRewards"].values()[1] == expected_profit
    assert float(tx.events["StrategyRewards"].values()[2]) == pytest.approx(expected_strategy_creator_fee)
    assert float(required_fund.balanceOf(accounts[0])) == pytest.approx(expected_strategy_creator_fee)

@pytest.fixture
def fund_through_proxy_with_2_strategies_and_hardworks(fund_through_proxy_with_2_strategies_deposit_and_hardwork, accounts):
    tx = fund_through_proxy_with_2_strategies_deposit_and_hardwork.doHardWork({'from': accounts[1]})
    
    return fund_through_proxy_with_2_strategies_deposit_and_hardwork

def test_withdraw_small(fund_through_proxy_with_2_strategies_and_hardworks, profitstrat_50_optimizer, token, accounts):
    
    required_fund = fund_through_proxy_with_2_strategies_and_hardworks
    shares_to_withdraw = 100 * (10 ** required_fund.decimals())
    price_per_share = required_fund.getPricePerShare()
    amount_to_withdraw = shares_to_withdraw * price_per_share / (10 ** required_fund.decimals())

    fund_balance_before = required_fund.balanceOf(accounts[3])
    token_balance_before = token.balanceOf(accounts[3])
    token_in_fund_before = token.balanceOf(required_fund)
    strategy_balance_before = profitstrat_50_optimizer.investedUnderlyingBalance()

    tx = required_fund.withdraw(shares_to_withdraw, {'from': accounts[3]})

    fund_balance_after = required_fund.balanceOf(accounts[3])
    token_balance_after = token.balanceOf(accounts[3])
    token_in_fund_after = token.balanceOf(required_fund)
    strategy_balance_after = profitstrat_50_optimizer.investedUnderlyingBalance()

    assert fund_balance_before - fund_balance_after == shares_to_withdraw
    assert float(token_balance_after - token_balance_before) == pytest.approx(amount_to_withdraw)
    assert float(token_in_fund_before - token_in_fund_after) == pytest.approx(amount_to_withdraw)
    assert strategy_balance_after == strategy_balance_before


def test_withdraw_large(fund_through_proxy_with_2_strategies_and_hardworks, profitstrat_50_optimizer, token, accounts):
    
    required_fund = fund_through_proxy_with_2_strategies_and_hardworks
    shares_to_withdraw = 500 * (10 ** required_fund.decimals())
    price_per_share = required_fund.getPricePerShare()
    amount_to_withdraw = shares_to_withdraw * price_per_share / (10 ** required_fund.decimals())

    fund_balance_before = required_fund.balanceOf(accounts[3])
    token_balance_before = token.balanceOf(accounts[3])
    token_in_fund_before = token.balanceOf(required_fund)
    strategy_balance_before = profitstrat_50_optimizer.investedUnderlyingBalance()

    tx = required_fund.withdraw(shares_to_withdraw, {'from': accounts[3]})

    fund_balance_after = required_fund.balanceOf(accounts[3])
    token_balance_after = token.balanceOf(accounts[3])
    token_in_fund_after = token.balanceOf(required_fund)
    strategy_balance_after = profitstrat_50_optimizer.investedUnderlyingBalance()

    assert fund_balance_before - fund_balance_after == shares_to_withdraw
    assert float(token_balance_after - token_balance_before) == pytest.approx(amount_to_withdraw)
    assert token_in_fund_after == 0
    assert float(strategy_balance_before - strategy_balance_after) == pytest.approx(amount_to_withdraw - token_in_fund_before)

def test_remove_strategies_from_optimizer(fund_through_proxy_with_2_strategies_and_hardworks, profitstrat_10_optimizer, profitstrat_50_optimizer, optimizer_strat, accounts, zero_account):
    
    assert optimizer_strat.activeStrategy() == profitstrat_50_optimizer
    strategy_balance_before = optimizer_strat.investedUnderlyingBalance()
    tx = optimizer_strat.removeStrategy(profitstrat_50_optimizer, {'from': accounts[1]})
    strategy_balance_after = optimizer_strat.investedUnderlyingBalance()
    
    assert optimizer_strat.activeStrategy() == profitstrat_10_optimizer
    assert tx.events["ActiveStrategyChangedOptimizer"].values() == [profitstrat_10_optimizer]
    assert strategy_balance_after == strategy_balance_before
    assert tx.events["StrategyRemovedOptimizer"].values() == [profitstrat_50_optimizer]

    tx = optimizer_strat.removeStrategy(profitstrat_10_optimizer, {'from': accounts[1]})

    strategy_balance_after = optimizer_strat.investedUnderlyingBalance()

    assert optimizer_strat.activeStrategy() == zero_account
    # assert tx.events["ActiveStrategyChangedOptimizer"].values() == [zero_account]
    assert strategy_balance_after == strategy_balance_before
    assert tx.events["StrategyRemovedOptimizer"].values() == [profitstrat_10_optimizer]

def test_remove_strategy_from_fund(fund_through_proxy_with_2_strategies_and_hardworks, optimizer_strat, token, accounts):

    required_fund = fund_through_proxy_with_2_strategies_and_hardworks

    total_value_locked_before = required_fund.totalValueLocked()
    strategy_balance_before = optimizer_strat.investedUnderlyingBalance()

    tx = required_fund.removeStrategy(optimizer_strat, {'from': accounts[0]})

    total_value_locked_after = required_fund.totalValueLocked()
    strategy_balance_after = optimizer_strat.investedUnderlyingBalance()

    assert required_fund.getStrategyList() == []
    assert tx.events["StrategyRemoved"].values() == [optimizer_strat]
    assert float(total_value_locked_before) == pytest.approx(total_value_locked_after)
    assert strategy_balance_after == 0
