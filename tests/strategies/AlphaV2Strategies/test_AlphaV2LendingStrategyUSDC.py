#!/usr/bin/python3

import pytest, brownie

strategy_weightage = 8000

@pytest.mark.require_network("mainnet-fork")
def test_deployment(AlphaV2LendingStrategyUSDC, interface, fund_through_proxy_usdc, usdc, accounts):
    alphav2strat = AlphaV2LendingStrategyUSDC.deploy(fund_through_proxy_usdc, {'from': accounts[0]})
    aBox_address = alphav2strat.aBox()
    aBox = interface.IAlphaV2(aBox_address)
    assert alphav2strat.name() == "AlphaV2LendingStrategyUSDC"
    assert alphav2strat.version() == "V1"
    assert aBox.uToken() == usdc

@pytest.fixture
def alphav2strat(AlphaV2LendingStrategyUSDC, fund_through_proxy_usdc, usdc, accounts):
    return AlphaV2LendingStrategyUSDC.deploy(fund_through_proxy_usdc, {'from': accounts[0]})


@pytest.mark.require_network("mainnet-fork")
def test_add_strategy(alphav2strat, fund_through_proxy_usdc, usdc, accounts):
    tx = fund_through_proxy_usdc.addStrategy(alphav2strat, strategy_weightage, 0, {'from': accounts[0]})

    assert fund_through_proxy_usdc.getStrategyList() == [alphav2strat]
    assert fund_through_proxy_usdc.getStrategy(alphav2strat)[0] == strategy_weightage
    assert fund_through_proxy_usdc.getStrategy(alphav2strat)[1] == 0
    assert tx.events["StrategyAdded"].values() == [alphav2strat, strategy_weightage, 0]

@pytest.fixture
def fund_through_proxy_usdc_with_strategy_and_deposit(fund_through_proxy_usdc, alphav2strat, usdc, test_usdc_account, accounts):
    tx = fund_through_proxy_usdc.addStrategy(alphav2strat, strategy_weightage, 0, {'from': accounts[0]})
    
    amount_to_deposit = 1000 * (10 ** usdc.decimals())
    usdc.approve(fund_through_proxy_usdc, amount_to_deposit, {'from': test_usdc_account})
    tx = fund_through_proxy_usdc.deposit(amount_to_deposit, {'from': test_usdc_account})

    return fund_through_proxy_usdc

@pytest.mark.require_network("mainnet-fork")
def test_hard_work(fund_through_proxy_usdc_with_strategy_and_deposit, alphav2strat, interface, usdc, accounts):

    assert alphav2strat.investedUnderlyingBalance() == 0

    amount_deposited = 1000 * (10 ** usdc.decimals())
    tx = fund_through_proxy_usdc_with_strategy_and_deposit.doHardWork({'from': accounts[0]})
    
    aBox_address = alphav2strat.aBox()
    aBox = interface.IAlphaV2(aBox_address)
    cToken_address = alphav2strat.cToken()
    cToken = interface.ICErc20(cToken_address)
    ctoken_price_per_share = cToken.exchangeRateStored()

    expected_tvl = amount_deposited
    expected_price_per_share = 10 ** fund_through_proxy_usdc_with_strategy_and_deposit.decimals()

    expected_underlying_balance = amount_deposited * strategy_weightage/10000

    assert float(alphav2strat.investedUnderlyingBalance()) == pytest.approx(expected_underlying_balance)
    assert float(fund_through_proxy_usdc_with_strategy_and_deposit.getPricePerShare()) == pytest.approx(expected_price_per_share)
    assert [float(v) for v in tx.events["HardWorkDone"].values()] == pytest.approx([expected_tvl, expected_price_per_share])
    assert aBox.balanceOf(alphav2strat) == (expected_underlying_balance / ctoken_price_per_share) * (10 ** 18)

@pytest.fixture
def fund_through_proxy_usdc_after_hardwork(fund_through_proxy_usdc_with_strategy_and_deposit, accounts):
    
    tx = fund_through_proxy_usdc_with_strategy_and_deposit.doHardWork({'from': accounts[0]})
    
    return fund_through_proxy_usdc_with_strategy_and_deposit


@pytest.mark.require_network("mainnet-fork")
def test_withdraw_small(fund_through_proxy_usdc_after_hardwork, alphav2strat, interface, usdc, test_usdc_account):
    
    shares_to_withdraw = 100 * (10 ** fund_through_proxy_usdc_after_hardwork.decimals())
    price_per_share = fund_through_proxy_usdc_after_hardwork.getPricePerShare()
    amount_to_withdraw = shares_to_withdraw * price_per_share / (10 ** fund_through_proxy_usdc_after_hardwork.decimals())

    fund_balance_before = fund_through_proxy_usdc_after_hardwork.balanceOf(test_usdc_account)
    usdc_balance_before = usdc.balanceOf(test_usdc_account)
    usdc_in_fund_before = usdc.balanceOf(fund_through_proxy_usdc_after_hardwork)
    strategy_balance_before = alphav2strat.investedUnderlyingBalance()

    tx = fund_through_proxy_usdc_after_hardwork.withdraw(shares_to_withdraw, {'from': test_usdc_account})

    fund_balance_after = fund_through_proxy_usdc_after_hardwork.balanceOf(test_usdc_account)
    usdc_balance_after = usdc.balanceOf(test_usdc_account)
    usdc_in_fund_after = usdc.balanceOf(fund_through_proxy_usdc_after_hardwork)
    strategy_balance_after = alphav2strat.investedUnderlyingBalance()

    assert fund_balance_before - fund_balance_after == shares_to_withdraw
    assert float(usdc_balance_after - usdc_balance_before) == pytest.approx(amount_to_withdraw)
    assert float(usdc_in_fund_before - usdc_in_fund_after) == pytest.approx(amount_to_withdraw)
    assert strategy_balance_after == strategy_balance_before


@pytest.mark.require_network("mainnet-fork")
def test_withdraw_large(fund_through_proxy_usdc_after_hardwork, alphav2strat, interface, usdc, test_usdc_account):
    
    shares_to_withdraw = 500 * (10 ** fund_through_proxy_usdc_after_hardwork.decimals())
    price_per_share = fund_through_proxy_usdc_after_hardwork.getPricePerShare()
    amount_to_withdraw = shares_to_withdraw * price_per_share / (10 ** fund_through_proxy_usdc_after_hardwork.decimals())

    fund_balance_before = fund_through_proxy_usdc_after_hardwork.balanceOf(test_usdc_account)
    usdc_balance_before = usdc.balanceOf(test_usdc_account)
    usdc_in_fund_before = usdc.balanceOf(fund_through_proxy_usdc_after_hardwork)
    strategy_balance_before = alphav2strat.investedUnderlyingBalance()

    tx = fund_through_proxy_usdc_after_hardwork.withdraw(shares_to_withdraw, {'from': test_usdc_account})

    fund_balance_after = fund_through_proxy_usdc_after_hardwork.balanceOf(test_usdc_account)
    usdc_balance_after = usdc.balanceOf(test_usdc_account)
    usdc_in_fund_after = usdc.balanceOf(fund_through_proxy_usdc_after_hardwork)
    strategy_balance_after = alphav2strat.investedUnderlyingBalance()

    assert fund_balance_before - fund_balance_after == shares_to_withdraw
    assert float(usdc_balance_after - usdc_balance_before) == pytest.approx(amount_to_withdraw)
    assert usdc_in_fund_after == 0
    assert float(strategy_balance_before - strategy_balance_after) == pytest.approx(amount_to_withdraw - usdc_in_fund_before, rel=1e-5)


@pytest.mark.require_network("mainnet-fork")
def test_remove_strategy(fund_through_proxy_usdc_after_hardwork, alphav2strat, interface, usdc, accounts):

    total_value_locked_before = fund_through_proxy_usdc_after_hardwork.totalValueLocked()
    strategy_balance_before = alphav2strat.investedUnderlyingBalance()

    tx = fund_through_proxy_usdc_after_hardwork.removeStrategy(alphav2strat, {'from': accounts[0]})

    total_value_locked_after = fund_through_proxy_usdc_after_hardwork.totalValueLocked()
    strategy_balance_after = alphav2strat.investedUnderlyingBalance()

    assert fund_through_proxy_usdc_after_hardwork.getStrategyList() == []
    assert tx.events["StrategyRemoved"].values() == [alphav2strat]
    assert float(total_value_locked_before) == pytest.approx(total_value_locked_after)
    assert strategy_balance_after == 0
