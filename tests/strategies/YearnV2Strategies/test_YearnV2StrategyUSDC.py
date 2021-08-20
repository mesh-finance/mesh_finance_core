#!/usr/bin/python3

import pytest, brownie

strategy_weightage = 8000

@pytest.mark.require_network("mainnet-fork")
def test_deployment(YearnV2StrategyUSDC, interface, fund_through_proxy_usdc, usdc, accounts):
    yearnv2strat = YearnV2StrategyUSDC.deploy(fund_through_proxy_usdc, {'from': accounts[0]})
    yVault_address = yearnv2strat.yVault()
    yVault = interface.IYVaultV2(yVault_address)
    assert yVault.token() == usdc

@pytest.fixture
def yearnv2strat(YearnV2StrategyUSDC, fund_through_proxy_usdc, usdc, accounts):
    return YearnV2StrategyUSDC.deploy(fund_through_proxy_usdc, {'from': accounts[0]})


@pytest.mark.require_network("mainnet-fork")
def test_add_strategy(yearnv2strat, fund_through_proxy_usdc, usdc, accounts):
    tx = fund_through_proxy_usdc.addStrategy(yearnv2strat, strategy_weightage, 0, {'from': accounts[0]})

    assert fund_through_proxy_usdc.getStrategyList() == [yearnv2strat]
    assert fund_through_proxy_usdc.getStrategy(yearnv2strat)[0] == strategy_weightage
    assert fund_through_proxy_usdc.getStrategy(yearnv2strat)[1] == 0
    assert tx.events["StrategyAdded"].values() == [yearnv2strat, strategy_weightage, 0]

@pytest.fixture
def fund_through_proxy_usdc_with_strategy_and_deposit(fund_through_proxy_usdc, yearnv2strat, usdc, test_usdc_account, accounts):
    tx = fund_through_proxy_usdc.addStrategy(yearnv2strat, strategy_weightage, 0, {'from': accounts[0]})
    
    amount_to_deposit = 1000 * (10 ** usdc.decimals())
    usdc.approve(fund_through_proxy_usdc, amount_to_deposit, {'from': test_usdc_account})
    tx = fund_through_proxy_usdc.deposit(amount_to_deposit, {'from': test_usdc_account})

    return fund_through_proxy_usdc

@pytest.mark.require_network("mainnet-fork")
def test_hard_work(fund_through_proxy_usdc_with_strategy_and_deposit, yearnv2strat, interface, usdc, accounts):

    assert yearnv2strat.investedUnderlyingBalance() == 0

    amount_deposited = 1000 * (10 ** usdc.decimals())
    tx = fund_through_proxy_usdc_with_strategy_and_deposit.doHardWork({'from': accounts[0]})

    yVault_address = yearnv2strat.yVault()
    yVault = interface.IYVaultV2(yVault_address)
    vault_price_per_share = yVault.pricePerShare()

    expected_tvl = amount_deposited
    expected_price_per_share = 10 ** fund_through_proxy_usdc_with_strategy_and_deposit.decimals()

    expected_underlying_balance = amount_deposited * strategy_weightage/10000

    assert float(yearnv2strat.investedUnderlyingBalance()) == pytest.approx(amount_deposited * strategy_weightage/10000)
    assert float(fund_through_proxy_usdc_with_strategy_and_deposit.getPricePerShare()) == pytest.approx(expected_price_per_share)
    assert [float(v) for v in tx.events["HardWorkDone"].values()] == pytest.approx([expected_tvl, expected_price_per_share])
    assert float(yVault.balanceOf(yearnv2strat)) == pytest.approx((expected_underlying_balance / vault_price_per_share) * (10 ** yVault.decimals()))

@pytest.fixture
def fund_through_proxy_usdc_after_hardwork(fund_through_proxy_usdc_with_strategy_and_deposit, accounts):
    
    tx = fund_through_proxy_usdc_with_strategy_and_deposit.doHardWork({'from': accounts[0]})
    
    return fund_through_proxy_usdc_with_strategy_and_deposit

@pytest.mark.require_network("mainnet-fork")
def test_withdraw_small(fund_through_proxy_usdc_after_hardwork, yearnv2strat, interface, usdc, test_usdc_account):
    
    shares_to_withdraw = 100 * (10 ** fund_through_proxy_usdc_after_hardwork.decimals())
    price_per_share = fund_through_proxy_usdc_after_hardwork.getPricePerShare()
    amount_to_withdraw = shares_to_withdraw * price_per_share / (10 ** fund_through_proxy_usdc_after_hardwork.decimals())

    fund_balance_before = fund_through_proxy_usdc_after_hardwork.balanceOf(test_usdc_account)
    usdc_balance_before = usdc.balanceOf(test_usdc_account)
    usdc_in_fund_before = usdc.balanceOf(fund_through_proxy_usdc_after_hardwork)
    strategy_balance_before = yearnv2strat.investedUnderlyingBalance()

    tx = fund_through_proxy_usdc_after_hardwork.withdraw(shares_to_withdraw, {'from': test_usdc_account})

    fund_balance_after = fund_through_proxy_usdc_after_hardwork.balanceOf(test_usdc_account)
    usdc_balance_after = usdc.balanceOf(test_usdc_account)
    usdc_in_fund_after = usdc.balanceOf(fund_through_proxy_usdc_after_hardwork)
    strategy_balance_after = yearnv2strat.investedUnderlyingBalance()

    assert fund_balance_before - fund_balance_after == shares_to_withdraw
    assert float(usdc_balance_after - usdc_balance_before) == pytest.approx(amount_to_withdraw)
    assert float(usdc_in_fund_before - usdc_in_fund_after) == pytest.approx(amount_to_withdraw)
    assert strategy_balance_after == strategy_balance_before


@pytest.mark.require_network("mainnet-fork")
def test_withdraw_large(fund_through_proxy_usdc_after_hardwork, yearnv2strat, interface, usdc, test_usdc_account):
    
    shares_to_withdraw = 500 * (10 ** fund_through_proxy_usdc_after_hardwork.decimals())
    price_per_share = fund_through_proxy_usdc_after_hardwork.getPricePerShare()
    amount_to_withdraw = shares_to_withdraw * price_per_share / (10 ** fund_through_proxy_usdc_after_hardwork.decimals())

    fund_balance_before = fund_through_proxy_usdc_after_hardwork.balanceOf(test_usdc_account)
    usdc_balance_before = usdc.balanceOf(test_usdc_account)
    usdc_in_fund_before = usdc.balanceOf(fund_through_proxy_usdc_after_hardwork)
    strategy_balance_before = yearnv2strat.investedUnderlyingBalance()

    tx = fund_through_proxy_usdc_after_hardwork.withdraw(shares_to_withdraw, {'from': test_usdc_account})

    fund_balance_after = fund_through_proxy_usdc_after_hardwork.balanceOf(test_usdc_account)
    usdc_balance_after = usdc.balanceOf(test_usdc_account)
    usdc_in_fund_after = usdc.balanceOf(fund_through_proxy_usdc_after_hardwork)
    strategy_balance_after = yearnv2strat.investedUnderlyingBalance()

    assert fund_balance_before - fund_balance_after == shares_to_withdraw
    assert float(usdc_balance_after - usdc_balance_before) == pytest.approx(amount_to_withdraw)
    assert usdc_in_fund_after == 0
    assert float(strategy_balance_before - strategy_balance_after) == pytest.approx(amount_to_withdraw - usdc_in_fund_before)


@pytest.mark.require_network("mainnet-fork")
def test_remove_strategy(fund_through_proxy_usdc_after_hardwork, yearnv2strat, interface, usdc, accounts):

    total_value_locked_before = fund_through_proxy_usdc_after_hardwork.totalValueLocked()
    strategy_balance_before = yearnv2strat.investedUnderlyingBalance()

    tx = fund_through_proxy_usdc_after_hardwork.removeStrategy(yearnv2strat, {'from': accounts[0]})

    total_value_locked_after = fund_through_proxy_usdc_after_hardwork.totalValueLocked()
    strategy_balance_after = yearnv2strat.investedUnderlyingBalance()

    assert fund_through_proxy_usdc_after_hardwork.getStrategyList() == []
    assert tx.events["StrategyRemoved"].values() == [yearnv2strat]
    assert float(total_value_locked_before) == pytest.approx(total_value_locked_after)
    assert strategy_balance_after == 0
