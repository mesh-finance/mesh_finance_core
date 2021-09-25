#!/usr/bin/python3

import pytest, brownie

strategy_weightage = 8000
strategy_fee_in_bps = 500


@pytest.fixture
def governance(accounts):
    return accounts[0]

@pytest.fixture
def fund_manager(accounts):
    return accounts[1]

@pytest.fixture
def optimizer_strat_creator(accounts):
    return accounts[5]

@pytest.fixture
def aavev2strat_creator(accounts):
    return accounts[6]

@pytest.fixture
def compound_strat_creator(accounts):
    return accounts[7]

@pytest.fixture
def dydxstrat_creator(accounts):
    return accounts[8]

@pytest.fixture
def optimizer_strat(OptimizerStrategyBase, fund_through_proxy_usdc, optimizer_strat_creator):
    return OptimizerStrategyBase.deploy(fund_through_proxy_usdc, {'from': optimizer_strat_creator})

@pytest.fixture
def aavev2strat(AaveV2LendingStrategyMainnet, optimizer_strat, aavev2strat_creator):
    return AaveV2LendingStrategyMainnet.deploy(optimizer_strat, {'from': aavev2strat_creator})

@pytest.fixture
def compound_strat(CompoundLendingStrategyMainnetUSDC, optimizer_strat, compound_strat_creator):
    return CompoundLendingStrategyMainnetUSDC.deploy(optimizer_strat, {'from': compound_strat_creator})

@pytest.fixture
def dydxstrat(DyDxLendingStrategyMainnetUSDC, optimizer_strat, dydxstrat_creator):
    return DyDxLendingStrategyMainnetUSDC.deploy(optimizer_strat, {'from': dydxstrat_creator})

def test_multi_interaction(fund_through_proxy_usdc, optimizer_strat, aavev2strat, compound_strat, dydxstrat, usdc, test_usdc_account, test_usdc_account_2, fund_manager):

    required_fund = fund_through_proxy_usdc
    fund_decimals = required_fund.decimals()
    price_per_share_decimals = required_fund.underlyingUnit()

    print("add aave strategy to optimizer")

    tx = required_fund.addStrategy(optimizer_strat, strategy_weightage, strategy_fee_in_bps, {'from': fund_manager})
    tx = optimizer_strat.addStrategy(aavev2strat, {'from': fund_manager})

    assert optimizer_strat.getStrategies()[0] == ["AaveV2LendingStrategyMainnet", aavev2strat, 0, aavev2strat.apr()]
    assert tx.events["StrategyAddedOptimizer"].values() == [aavev2strat]
    
    print("test_usdc_account deposits 1000 usdc")
    
    price_per_share = required_fund.getPricePerShare()
    usdc_balance_before = usdc.balanceOf(test_usdc_account)
    amount_to_deposit = amount_deposited = 1000 * (10 ** usdc.decimals())
    usdc.approve(required_fund, amount_to_deposit, {'from': test_usdc_account})
    required_fund.deposit(amount_to_deposit, {'from': test_usdc_account})
    usdc_balance_after = usdc.balanceOf(test_usdc_account)

    assert required_fund.balanceOf(test_usdc_account) == (1000 * (10 ** fund_decimals))/(price_per_share/price_per_share_decimals)
    assert required_fund.underlyingBalanceWithInvestmentForHolder(test_usdc_account) == amount_to_deposit
    assert usdc_balance_before - usdc_balance_after == amount_to_deposit


    print("hard work")

    tx = required_fund.doHardWork({'from': fund_manager})

    assert optimizer_strat.activeStrategy() == aavev2strat
    assert tx.events["ActiveStrategyChangedOptimizer"].values() == [aavev2strat]
    assert optimizer_strat.investedUnderlyingBalance() == aavev2strat.investedUnderlyingBalance()
    assert float(aavev2strat.investedUnderlyingBalance()) == pytest.approx((strategy_weightage/10000 * amount_deposited))


    print("test_usdc_account_2 deposits 1000 usdc")
    
    price_per_share = required_fund.getPricePerShare()
    usdc_balance_before = usdc.balanceOf(test_usdc_account_2)
    amount_to_deposit = 1000 * (10 ** usdc.decimals())
    amount_deposited = amount_deposited + amount_to_deposit
    usdc.approve(required_fund, amount_to_deposit, {'from': test_usdc_account_2})
    required_fund.deposit(amount_to_deposit, {'from': test_usdc_account_2})
    usdc_balance_after = usdc.balanceOf(test_usdc_account_2)

    assert float(required_fund.balanceOf(test_usdc_account_2)) == pytest.approx((1000 * (10 ** fund_decimals))/(price_per_share/price_per_share_decimals))
    assert float(required_fund.underlyingBalanceWithInvestmentForHolder(test_usdc_account_2)) == pytest.approx(amount_to_deposit)
    assert usdc_balance_before - usdc_balance_after == amount_to_deposit

    print("add compound strategy to optimizer")
    
    tx = optimizer_strat.addStrategy(compound_strat, {'from': fund_manager})

    assert optimizer_strat.getStrategies()[1] == ["CompoundLendingStrategyMainnetUSDC", compound_strat, 0, compound_strat.apr()]
    assert tx.events["StrategyAddedOptimizer"].values() == [compound_strat]

    print("hard work")

    tx = required_fund.doHardWork({'from': fund_manager})

    if (compound_strat.apr() > aavev2strat.apr()):
        higher_apr_strat = compound_strat
        assert optimizer_strat.activeStrategy() == compound_strat
        assert tx.events["ActiveStrategyChangedOptimizer"].values() == [compound_strat]
        assert optimizer_strat.investedUnderlyingBalance() == compound_strat.investedUnderlyingBalance()
        assert float(compound_strat.investedUnderlyingBalance()) == pytest.approx((strategy_weightage/10000 * amount_deposited))
    else:
        higher_apr_strat = aavev2strat
        assert optimizer_strat.activeStrategy() == aavev2strat
        assert optimizer_strat.investedUnderlyingBalance() == aavev2strat.investedUnderlyingBalance()
        assert float(aavev2strat.investedUnderlyingBalance()) == pytest.approx((strategy_weightage/10000 * amount_deposited))

    print("add dydx strategy to optimizer")

    tx = optimizer_strat.addStrategy(dydxstrat, {'from': fund_manager})

    assert optimizer_strat.getStrategies()[2] == ["DyDxLendingStrategyMainnetUSDC", dydxstrat, 0, dydxstrat.apr()]
    assert tx.events["StrategyAddedOptimizer"].values() == [dydxstrat]

    print("hard work")

    tx = required_fund.doHardWork({'from': fund_manager})

    if (dydxstrat.apr() > higher_apr_strat.apr()):
        higher_apr_strat = dydxstrat
        assert optimizer_strat.activeStrategy() == dydxstrat
        assert tx.events["ActiveStrategyChangedOptimizer"].values() == [dydxstrat]
        assert optimizer_strat.investedUnderlyingBalance() == dydxstrat.investedUnderlyingBalance()
        assert float(dydxstrat.investedUnderlyingBalance()) == pytest.approx((strategy_weightage/10000 * amount_deposited))
    else:
        assert optimizer_strat.activeStrategy() == higher_apr_strat
        assert optimizer_strat.investedUnderlyingBalance() == higher_apr_strat.investedUnderlyingBalance()
        assert float(higher_apr_strat.investedUnderlyingBalance()) == pytest.approx((strategy_weightage/10000 * amount_deposited))

    
