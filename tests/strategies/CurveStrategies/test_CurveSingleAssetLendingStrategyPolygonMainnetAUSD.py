#!/usr/bin/python3

import pytest, brownie

strategy_weightage = 8000

@pytest.mark.require_network("matic-fork")
def test_deployment(CurveSingleAssetLendingStrategyPolygonMainnetAUSD, interface, fund_through_proxy_usdc, usdc, accounts):
    curvestrat = CurveSingleAssetLendingStrategyPolygonMainnetAUSD.deploy(fund_through_proxy_usdc, {'from': accounts[0]})
    is_wrapped_pool = curvestrat.isWrappedPool()
    use_underlying = curvestrat.useUnderlying()
    crv_pool_address = curvestrat.crvPool()
    crv_pool = interface.ICurveFi(crv_pool_address)
    underlying_address = curvestrat.underlying()
    crv_id = 4
    if (not is_wrapped_pool or (is_wrapped_pool and not use_underlying)):
        if (crv_pool.coins(0) == underlying_address):
            crv_id = 0
        elif (crv_pool.coins(1) == underlying_address):
            crv_id = underlying_address
        elif (crv_pool.coins(2) == underlying_address):
            crv_id = 2
    else:
        if (crv_pool.underlying_coins(0) == underlying_address):
            crv_id = 0
        elif (crv_pool.underlying_coins(1) == underlying_address):
            crv_id = 1
        elif (crv_pool.underlying_coins(2) == underlying_address):
            crv_id = 2
    assert crv_id < 3
    assert crv_id == curvestrat.crvId()

@pytest.fixture
def curvestrat(CurveSingleAssetLendingStrategyPolygonMainnetAUSD, fund_through_proxy_usdc, usdc, accounts):
    return CurveSingleAssetLendingStrategyPolygonMainnetAUSD.deploy(fund_through_proxy_usdc, {'from': accounts[0]})


@pytest.mark.require_network("matic-fork")
def test_add_strategy(curvestrat, fund_through_proxy_usdc, usdc, accounts):
    tx = fund_through_proxy_usdc.addStrategy(curvestrat, strategy_weightage, 0, {'from': accounts[0]})

    assert fund_through_proxy_usdc.getStrategyList() == [curvestrat]
    assert fund_through_proxy_usdc.getStrategy(curvestrat)[0] == strategy_weightage
    assert fund_through_proxy_usdc.getStrategy(curvestrat)[1] == 0
    assert tx.events["StrategyAdded"].values() == [curvestrat, strategy_weightage, 0]

@pytest.fixture
def fund_through_proxy_usdc_with_strategy_and_deposit(fund_through_proxy_usdc, curvestrat, usdc, test_usdc_account, accounts):
    tx = fund_through_proxy_usdc.addStrategy(curvestrat, strategy_weightage, 0, {'from': accounts[0]})
    
    amount_to_deposit = 1000 * (10 ** usdc.decimals())
    usdc.approve(fund_through_proxy_usdc, amount_to_deposit, {'from': test_usdc_account})
    tx = fund_through_proxy_usdc.deposit(amount_to_deposit, {'from': test_usdc_account})

    return fund_through_proxy_usdc

@pytest.mark.require_network("matic-fork")
def test_hard_work(fund_through_proxy_usdc_with_strategy_and_deposit, curvestrat, interface, usdc, accounts):

    assert curvestrat.investedUnderlyingBalance() == 0

    amount_deposited = 1000 * (10 ** usdc.decimals())
    
    crv_pool_address = curvestrat.crvPool()
    crv_pool = interface.ICurveFi(crv_pool_address)
    crv_pool_gauge_address = curvestrat.crvPoolGauge()
    crv_pool_gauge = interface.IERC20(crv_pool_gauge_address)
    crv_id = curvestrat.crvId()
    expected_underlying_balance = amount_deposited * strategy_weightage/10000
    amounts = [0, 0, 0]
    amounts[crv_id] = expected_underlying_balance
    final_expected_balance = crv_pool.calc_token_amount(amounts, False)
    
    tx = fund_through_proxy_usdc_with_strategy_and_deposit.doHardWork({'from': accounts[0]})

    expected_tvl = amount_deposited
    expected_price_per_share = 10 ** fund_through_proxy_usdc_with_strategy_and_deposit.decimals()

    assert float(curvestrat.investedUnderlyingBalance()) == pytest.approx(amount_deposited * strategy_weightage/10000, rel=1e-3)
    assert float(fund_through_proxy_usdc_with_strategy_and_deposit.getPricePerShare()) == pytest.approx(expected_price_per_share, rel=1e-3)
    assert [float(v) for v in tx.events["HardWorkDone"].values()] == pytest.approx([expected_tvl, expected_price_per_share], rel=1e-3)
    assert float(crv_pool_gauge.balanceOf(curvestrat)) == pytest.approx(final_expected_balance, rel=1e-3)

@pytest.fixture
def fund_through_proxy_usdc_after_hardwork(fund_through_proxy_usdc_with_strategy_and_deposit, accounts):
    
    tx = fund_through_proxy_usdc_with_strategy_and_deposit.doHardWork({'from': accounts[0]})
    
    return fund_through_proxy_usdc_with_strategy_and_deposit


@pytest.mark.require_network("matic-fork")
def test_withdraw_small(fund_through_proxy_usdc_after_hardwork, curvestrat, interface, usdc, test_usdc_account):
    
    shares_to_withdraw = 100 * (10 ** fund_through_proxy_usdc_after_hardwork.decimals())
    price_per_share = fund_through_proxy_usdc_after_hardwork.getPricePerShare()
    amount_to_withdraw = shares_to_withdraw * price_per_share / (10 ** fund_through_proxy_usdc_after_hardwork.decimals())

    fund_balance_before = fund_through_proxy_usdc_after_hardwork.balanceOf(test_usdc_account)
    usdc_balance_before = usdc.balanceOf(test_usdc_account)
    usdc_in_fund_before = usdc.balanceOf(fund_through_proxy_usdc_after_hardwork)
    strategy_balance_before = curvestrat.investedUnderlyingBalance()

    tx = fund_through_proxy_usdc_after_hardwork.withdraw(shares_to_withdraw, {'from': test_usdc_account})

    fund_balance_after = fund_through_proxy_usdc_after_hardwork.balanceOf(test_usdc_account)
    usdc_balance_after = usdc.balanceOf(test_usdc_account)
    usdc_in_fund_after = usdc.balanceOf(fund_through_proxy_usdc_after_hardwork)
    strategy_balance_after = curvestrat.investedUnderlyingBalance()

    assert fund_balance_before - fund_balance_after == shares_to_withdraw
    assert float(usdc_balance_after - usdc_balance_before) == pytest.approx(amount_to_withdraw)
    assert float(usdc_in_fund_before - usdc_in_fund_after) == pytest.approx(amount_to_withdraw)
    assert float(strategy_balance_after) == pytest.approx(strategy_balance_before)


@pytest.mark.require_network("matic-fork")
def test_withdraw_large(fund_through_proxy_usdc_after_hardwork, curvestrat, interface, usdc, test_usdc_account):
    
    shares_to_withdraw = 500 * (10 ** fund_through_proxy_usdc_after_hardwork.decimals())
    price_per_share = fund_through_proxy_usdc_after_hardwork.getPricePerShare()
    amount_to_withdraw = shares_to_withdraw * price_per_share / (10 ** fund_through_proxy_usdc_after_hardwork.decimals())

    fund_balance_before = fund_through_proxy_usdc_after_hardwork.balanceOf(test_usdc_account)
    usdc_balance_before = usdc.balanceOf(test_usdc_account)
    usdc_in_fund_before = usdc.balanceOf(fund_through_proxy_usdc_after_hardwork)
    strategy_balance_before = curvestrat.investedUnderlyingBalance()

    tx = fund_through_proxy_usdc_after_hardwork.withdraw(shares_to_withdraw, {'from': test_usdc_account})

    fund_balance_after = fund_through_proxy_usdc_after_hardwork.balanceOf(test_usdc_account)
    usdc_balance_after = usdc.balanceOf(test_usdc_account)
    usdc_in_fund_after = usdc.balanceOf(fund_through_proxy_usdc_after_hardwork)
    strategy_balance_after = curvestrat.investedUnderlyingBalance()

    assert fund_balance_before - fund_balance_after == shares_to_withdraw
    assert float(usdc_balance_after - usdc_balance_before) == pytest.approx(amount_to_withdraw, rel=1e-3)
    assert usdc_in_fund_after == 0
    assert float(strategy_balance_before - strategy_balance_after) == pytest.approx(amount_to_withdraw - usdc_in_fund_before, rel=1e-3)


@pytest.mark.require_network("matic-fork")
def test_remove_strategy(fund_through_proxy_usdc_after_hardwork, curvestrat, interface, usdc, accounts):

    total_value_locked_before = fund_through_proxy_usdc_after_hardwork.totalValueLocked()
    strategy_balance_before = curvestrat.investedUnderlyingBalance()

    tx = fund_through_proxy_usdc_after_hardwork.removeStrategy(curvestrat, {'from': accounts[0]})

    total_value_locked_after = fund_through_proxy_usdc_after_hardwork.totalValueLocked()
    strategy_balance_after = curvestrat.investedUnderlyingBalance()

    assert fund_through_proxy_usdc_after_hardwork.getStrategyList() == []
    assert tx.events["StrategyRemoved"].values() == [curvestrat]
    assert float(total_value_locked_before) == pytest.approx(total_value_locked_after)
    assert strategy_balance_after == 0
