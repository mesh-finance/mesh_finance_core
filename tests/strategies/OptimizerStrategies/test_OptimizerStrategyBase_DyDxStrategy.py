#!/usr/bin/python3

import pytest, brownie

strategy_weightage = 8000

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_deployment(OptimizerStrategyBase, fund_through_proxy_usdc, usdc, accounts):
    optimizer_strat = OptimizerStrategyBase.deploy(fund_through_proxy_usdc, {'from': accounts[0]})
    assert optimizer_strat.underlying() == usdc
    assert optimizer_strat.fund() == fund_through_proxy_usdc
    assert optimizer_strat.canNotSweep(usdc) == True
    assert optimizer_strat.investActivated() == True

@pytest.fixture
def optimizer_strat(OptimizerStrategyBase, fund_through_proxy_usdc, accounts):
    return OptimizerStrategyBase.deploy(fund_through_proxy_usdc, {'from': accounts[0]})

@pytest.fixture
def dydxstrat(DyDxLendingStrategyMainnetUSDC, optimizer_strat, accounts):
    return DyDxLendingStrategyMainnetUSDC.deploy(optimizer_strat, {'from': accounts[0]})

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_add_dydx_strategy_to_optimizer(dydxstrat, optimizer_strat, accounts):
    tx = optimizer_strat.addStrategy(dydxstrat, {'from': accounts[1]})

    assert optimizer_strat.getStrategies()[0] == ["DyDxLendingStrategyMainnetUSDC", dydxstrat, 0, dydxstrat.apr()]
    assert tx.events["StrategyAddedOptimizer"].values() == [dydxstrat]

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_add_same_strategy_to_optimizer(dydxstrat, optimizer_strat, accounts):
    optimizer_strat.addStrategy(dydxstrat, {'from': accounts[1]})

    with brownie.reverts("The strategy is already added in this optimizer"):
        optimizer_strat.addStrategy(dydxstrat, {'from': accounts[1]})

@pytest.fixture
def fund_through_proxy_with_dydx_strategy_and_deposit(fund_through_proxy_usdc, optimizer_strat, dydxstrat, accounts, usdc, test_usdc_account):
    tx = fund_through_proxy_usdc.addStrategy(optimizer_strat, strategy_weightage, 500, {'from': accounts[1]})
    tx = optimizer_strat.addStrategy(dydxstrat, {'from': accounts[1]})
    
    amount_to_deposit = 1000 * (10 ** usdc.decimals())
    usdc.approve(fund_through_proxy_usdc, amount_to_deposit, {'from': test_usdc_account})
    fund_through_proxy_usdc.deposit(amount_to_deposit, {'from': test_usdc_account})
    
    return fund_through_proxy_usdc

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_set_invest_activate_with_random_address(fund_through_proxy_with_dydx_strategy_and_deposit, optimizer_strat, accounts):
    with brownie.reverts("The sender has to be the governance or fund manager"):
        optimizer_strat.setInvestActivated(False, {'from': accounts[7]})

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_fund_with_dydx_strategy_hardwork_with_optimizer_invest_activate_false(fund_through_proxy_with_dydx_strategy_and_deposit, optimizer_strat, dydxstrat, usdc, accounts, interface):
    deposited_amount = 1000 * (10 ** usdc.decimals())
    required_fund = fund_through_proxy_with_dydx_strategy_and_deposit
    usdc_balance_in_dydx_before = dydxstrat.investedUnderlyingBalance()
    # usdc_balance_in_optimizer_before = dydxstrat.investedUnderlyingBalance()
    usdc_balance_in_optimizer_before = interface.IERC20(usdc).balanceOf(optimizer_strat)
    optimizer_strat.setInvestActivated(False, {'from': accounts[1]})
    required_fund.doHardWork({'from': accounts[1]})
    usdc_balance_in_dydx_after = dydxstrat.investedUnderlyingBalance()
    # usdc_balance_in_optimizer_after = dydxstrat.investedUnderlyingBalance()
    usdc_balance_in_optimizer_after = interface.IERC20(usdc).balanceOf(optimizer_strat)
    assert usdc_balance_in_dydx_before == usdc_balance_in_dydx_after == 0
    assert usdc_balance_in_optimizer_before == 0
    assert usdc_balance_in_optimizer_after == deposited_amount*strategy_weightage/10000

def test_deposit_and_hard_work_with_dydx_strategy(fund_through_proxy_with_dydx_strategy_and_deposit, optimizer_strat, dydxstrat, usdc, accounts):
    required_fund = fund_through_proxy_with_dydx_strategy_and_deposit
    amount_deposited = 1000 * (10 ** usdc.decimals())
    tx = required_fund.doHardWork({'from': accounts[1]})

    assert optimizer_strat.activeStrategy() == dydxstrat
    assert tx.events["ActiveStrategyChangedOptimizer"].values() == [dydxstrat]
    assert optimizer_strat.investedUnderlyingBalance() == dydxstrat.investedUnderlyingBalance()
    assert float(dydxstrat.investedUnderlyingBalance()) == pytest.approx((strategy_weightage/10000 * amount_deposited))

@pytest.fixture
def fund_with_deposit_and_hard_work_with_dydx_strategy(fund_through_proxy_with_dydx_strategy_and_deposit, accounts):
    required_fund = fund_through_proxy_with_dydx_strategy_and_deposit
    required_fund.doHardWork({'from': accounts[1]})
    return required_fund

@pytest.fixture
def profitstrat_1_optimizer(ProfitStrategy, optimizer_strat, accounts):
    return ProfitStrategy.deploy(optimizer_strat, 100, {'from': accounts[5]})

# this test is done considering dydxstrat apr > 1% (profit strategy's apr)
def test_fund_with_dydx_strategy_and_profit1_strategy_hardwork(fund_with_deposit_and_hard_work_with_dydx_strategy, optimizer_strat, dydxstrat, profitstrat_1_optimizer, accounts):
    optimizer_strat.addStrategy(profitstrat_1_optimizer, {'from': accounts[1]})
    fund_with_deposit_and_hard_work_with_dydx_strategy.doHardWork({'from':accounts[1]})
    assert optimizer_strat.getStrategies()[0] == ["DyDxLendingStrategyMainnetUSDC", dydxstrat, dydxstrat.investedUnderlyingBalance(), dydxstrat.apr()]
    assert optimizer_strat.getStrategies()[1] == ["ProfitStrategy", profitstrat_1_optimizer, 0, 10000]
    assert optimizer_strat.activeStrategy() == dydxstrat
    assert optimizer_strat.investedUnderlyingBalance() == dydxstrat.investedUnderlyingBalance()

@pytest.fixture
def profitstrat_50_optimizer(ProfitStrategy, optimizer_strat, accounts):
    return ProfitStrategy.deploy(optimizer_strat, 5000, {'from': accounts[5]})

def test_fund_with_dydx_strategy_and_profit50_strategy_hardwork(fund_with_deposit_and_hard_work_with_dydx_strategy, optimizer_strat, dydxstrat, profitstrat_50_optimizer, accounts, usdc):
    deposited_amount = 1000 * (10 ** usdc.decimals())
    optimizer_strat.addStrategy(profitstrat_50_optimizer, {'from': accounts[1]})
    fund_with_deposit_and_hard_work_with_dydx_strategy.doHardWork({'from':accounts[1]})
    assert optimizer_strat.getStrategies()[0] == ["DyDxLendingStrategyMainnetUSDC", dydxstrat, 0, dydxstrat.apr()]
    assert optimizer_strat.getStrategies()[1][0] == "ProfitStrategy"
    assert float(optimizer_strat.getStrategies()[1][2]) == pytest.approx((deposited_amount*strategy_weightage)/10000)
    assert optimizer_strat.activeStrategy() == profitstrat_50_optimizer
    assert optimizer_strat.investedUnderlyingBalance() == profitstrat_50_optimizer.investedUnderlyingBalance()

@pytest.fixture
def fund_with_deposit_and_hard_work_with_aave_strategy_and_profit1_strategy_hardwork(fund_through_proxy_with_dydx_strategy_and_deposit, optimizer_strat, accounts, profitstrat_1_optimizer):
    optimizer_strat.addStrategy(profitstrat_1_optimizer, {'from': accounts[1]})
    required_fund = fund_through_proxy_with_dydx_strategy_and_deposit
    required_fund.doHardWork({'from':accounts[1]})
    return required_fund

def test_withdraw_small(fund_with_deposit_and_hard_work_with_aave_strategy_and_profit1_strategy_hardwork, dydxstrat, usdc, test_usdc_account):    
    required_fund = fund_with_deposit_and_hard_work_with_aave_strategy_and_profit1_strategy_hardwork
    shares_to_withdraw = 100 * (10 ** required_fund.decimals())
    price_per_share = required_fund.getPricePerShare()
    amount_to_withdraw = shares_to_withdraw * price_per_share / (10 ** required_fund.decimals())

    fund_balance_before = required_fund.balanceOf(test_usdc_account)
    usdc_balance_before = usdc.balanceOf(test_usdc_account)
    token_in_fund_before = usdc.balanceOf(required_fund)
    strategy_balance_before = dydxstrat.investedUnderlyingBalance()

    required_fund.withdraw(shares_to_withdraw, {'from': test_usdc_account})

    fund_balance_after = required_fund.balanceOf(test_usdc_account)
    usdc_balance_after = usdc.balanceOf(test_usdc_account)
    token_in_fund_after = usdc.balanceOf(required_fund)
    strategy_balance_after = dydxstrat.investedUnderlyingBalance()

    assert fund_balance_before - fund_balance_after == shares_to_withdraw
    assert float(usdc_balance_after - usdc_balance_before) == pytest.approx(amount_to_withdraw, rel=1e-5)
    assert float(token_in_fund_before - token_in_fund_after) == pytest.approx(amount_to_withdraw, rel=1e-5)
    assert float(strategy_balance_after) == pytest.approx(strategy_balance_before)

def test_withdraw_large(fund_with_deposit_and_hard_work_with_aave_strategy_and_profit1_strategy_hardwork, dydxstrat, usdc, test_usdc_account):
    required_fund = fund_with_deposit_and_hard_work_with_aave_strategy_and_profit1_strategy_hardwork
    shares_to_withdraw = 600 * (10 ** required_fund.decimals())
    # TODO: everywhere when we run price per share from script we get 999999 but when we do it on terminal we get 1000000. This makes many of these testsf
    price_per_share = required_fund.getPricePerShare()
    usdc_amount_to_withdraw = (shares_to_withdraw * price_per_share) / (10 ** required_fund.decimals())

    fund_balance_before = required_fund.balanceOf(test_usdc_account)
    usdc_balance_before = usdc.balanceOf(test_usdc_account)
    usdc_in_fund_before = usdc.balanceOf(required_fund)
    strategy_balance_before = dydxstrat.investedUnderlyingBalance()

    required_fund.withdraw(shares_to_withdraw, {'from': test_usdc_account})

    fund_balance_after = required_fund.balanceOf(test_usdc_account)
    usdc_balance_after = usdc.balanceOf(test_usdc_account)
    token_in_fund_after = usdc.balanceOf(required_fund)
    strategy_balance_after = dydxstrat.investedUnderlyingBalance()

    assert fund_balance_before - fund_balance_after == shares_to_withdraw
    assert float(usdc_balance_after - usdc_balance_before) == pytest.approx(usdc_amount_to_withdraw, rel=1e-5)
    assert token_in_fund_after == 0
    assert float(strategy_balance_before - strategy_balance_after) == pytest.approx(usdc_amount_to_withdraw - usdc_in_fund_before, rel=1e-5)

def test_remove_strategies_from_optimizer(fund_with_deposit_and_hard_work_with_aave_strategy_and_profit1_strategy_hardwork, profitstrat_1_optimizer, dydxstrat, optimizer_strat, accounts, zero_account):
    
    assert optimizer_strat.activeStrategy() == dydxstrat
    assert optimizer_strat.getStrategies()[1][1] == profitstrat_1_optimizer
    strategy_balance_before = optimizer_strat.investedUnderlyingBalance()
    tx = optimizer_strat.removeStrategy(dydxstrat, {'from': accounts[1]})
    strategy_balance_after = optimizer_strat.investedUnderlyingBalance()
    
    assert optimizer_strat.activeStrategy() == profitstrat_1_optimizer
    assert tx.events["ActiveStrategyChangedOptimizer"].values() == [profitstrat_1_optimizer]
    assert float(strategy_balance_after) == pytest.approx(strategy_balance_before)
    assert tx.events["StrategyRemovedOptimizer"].values() == [dydxstrat]

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

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_sweep_with_random_address(fund_with_deposit_and_hard_work_with_dydx_strategy, optimizer_strat, accounts, interface): 
    uni_token_address = "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984"
    random_uni_holder = "0x47173b170c64d16393a52e6c480b3ad8c302ba1e"
    interface.ERC20(uni_token_address).transfer(
        optimizer_strat,
        200 * (10 ** 18),
        {'from':random_uni_holder}
    )
    with brownie.reverts("Not governance"):
        optimizer_strat.sweep(uni_token_address, random_uni_holder, {'from': accounts[7]})

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_sweep_with_governance(fund_with_deposit_and_hard_work_with_dydx_strategy, optimizer_strat, accounts, interface): 
    uni_token_address = "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984"
    random_uni_holder = "0x47173b170c64d16393a52e6c480b3ad8c302ba1e"
    uni_to_transfer = 200 * (10 ** 18)
    uni_balance_before_user_transfer = interface.ERC20(uni_token_address).balanceOf(random_uni_holder)
    interface.ERC20(uni_token_address).transfer(
        optimizer_strat,
        uni_to_transfer,
        {'from':random_uni_holder}
    )
    uni_balance_after_user_transfer = interface.ERC20(uni_token_address).balanceOf(random_uni_holder)
    assert uni_balance_before_user_transfer == uni_balance_after_user_transfer + uni_to_transfer
    optimizer_strat.sweep(uni_token_address, random_uni_holder, {'from': accounts[0]})
    uni_balance_after_strategy_transfer = interface.ERC20(uni_token_address).balanceOf(random_uni_holder)
    assert uni_balance_after_strategy_transfer == uni_balance_after_user_transfer + uni_to_transfer

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_sweep_underlying_by_governance(fund_through_proxy_with_dydx_strategy_and_deposit, optimizer_strat, accounts, interface, usdc, test_usdc_account):
    interface.ERC20(usdc).transfer(
        optimizer_strat,
        200 * (10 ** 6),
        {'from':test_usdc_account}
    )
    with brownie.reverts("Token is restricted"):
        optimizer_strat.sweep(usdc, test_usdc_account, {'from': accounts[0]})

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_sweep_to_zero_account_by_governance(fund_through_proxy_with_dydx_strategy_and_deposit, optimizer_strat, accounts, interface, zero_account):
    uni_token_address = "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984"
    random_uni_holder = "0x47173b170c64d16393a52e6c480b3ad8c302ba1e"
    uni_to_transfer = 200 * (10 ** 18)
    interface.ERC20(uni_token_address).transfer(
        optimizer_strat,
        uni_to_transfer,
        {'from':random_uni_holder}
    )
    with brownie.reverts("Can not sweep to zero address"):
        optimizer_strat.sweep(uni_token_address, zero_account, {'from': accounts[0]})
