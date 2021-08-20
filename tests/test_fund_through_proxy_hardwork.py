#!/usr/bin/python3

import pytest, brownie

def test_hard_work_single_strategy_with_random_account(fund_through_proxy, accounts, token, profit_strategy_10):
    token.mint(accounts[3], 100000000, {'from': accounts[0]})
    token.approve(fund_through_proxy, 50000000, {'from': accounts[3]})
    fund_through_proxy.deposit(50000000, {'from': accounts[3]})

    token.grantRole(brownie.web3.keccak(text="MINTER_ROLE"), profit_strategy_10, {'from': accounts[0]})
    fund_through_proxy.addStrategy(profit_strategy_10, 5000, 0, {'from': accounts[1]})

    with brownie.reverts("Not fund manager or relayer"):
        tx = fund_through_proxy.doHardWork({'from': accounts[0]})

def test_hard_work_single_strategy_via_fund_manager(fund_through_proxy, accounts, token, profit_strategy_10):
    token.mint(accounts[3], 100000000, {'from': accounts[0]})
    token.approve(fund_through_proxy, 50000000, {'from': accounts[3]})
    fund_through_proxy.deposit(50000000, {'from': accounts[3]})

    token.grantRole(brownie.web3.keccak(text="MINTER_ROLE"), profit_strategy_10, {'from': accounts[0]})
    fund_through_proxy.addStrategy(profit_strategy_10, 5000, 0, {'from': accounts[1]})

    tx = fund_through_proxy.doHardWork({'from': accounts[1]})
    profit_strategy_10.investAllUnderlying({'from': accounts[0]})

    expected_tvl = ((50/100 * 50000000) * (1 + 10/100)) + (50/100 * 50000000)
    expected_price_per_share = fund_through_proxy.underlyingUnit() * (((50/100 * 50000000) * (1 + 10/100)) + (50/100 * 50000000)) / 50000000

    assert profit_strategy_10.investedUnderlyingBalance() == (50/100 * 50000000) * (1 + 10/100)
    assert fund_through_proxy.getPricePerShare() == expected_price_per_share
    assert tx.events["HardWorkDone"].values() == [50000000, fund_through_proxy.underlyingUnit()]

def test_hard_work_single_strategy_via_relayer(fund_through_proxy, accounts, token, profit_strategy_10):
    token.mint(accounts[3], 100000000, {'from': accounts[0]})
    token.approve(fund_through_proxy, 50000000, {'from': accounts[3]})
    fund_through_proxy.deposit(50000000, {'from': accounts[3]})

    token.grantRole(brownie.web3.keccak(text="MINTER_ROLE"), profit_strategy_10, {'from': accounts[0]})
    fund_through_proxy.addStrategy(profit_strategy_10, 5000, 0, {'from': accounts[1]})

    tx = fund_through_proxy.doHardWork({'from': accounts[3]})
    profit_strategy_10.investAllUnderlying({'from': accounts[0]})

    expected_tvl = ((50/100 * 50000000) * (1 + 10/100)) + (50/100 * 50000000)
    expected_price_per_share = fund_through_proxy.underlyingUnit() * (((50/100 * 50000000) * (1 + 10/100)) + (50/100 * 50000000)) / 50000000

    assert profit_strategy_10.investedUnderlyingBalance() == (50/100 * 50000000) * (1 + 10/100)
    assert fund_through_proxy.getPricePerShare() == expected_price_per_share
    assert tx.events["HardWorkDone"].values() == [50000000, fund_through_proxy.underlyingUnit()]

def test_multiple_hard_work_single_strategy(fund_through_proxy, accounts, token, profit_strategy_10):
    token.mint(accounts[3], 100000000, {'from': accounts[0]})
    token.approve(fund_through_proxy, 50000000, {'from': accounts[3]})
    fund_through_proxy.deposit(50000000, {'from': accounts[3]})

    token.grantRole(brownie.web3.keccak(text="MINTER_ROLE"), profit_strategy_10, {'from': accounts[0]})
    fund_through_proxy.addStrategy(profit_strategy_10, 5000, 0, {'from': accounts[1]})

    tx = fund_through_proxy.doHardWork({'from': accounts[1]})
    profit_strategy_10.investAllUnderlying({'from': accounts[0]})

    token.approve(fund_through_proxy, 50000000, {'from': accounts[3]})
    fund_through_proxy.deposit(50000000, {'from': accounts[3]})

    tx = fund_through_proxy.doHardWork({'from': accounts[1]})

    assert profit_strategy_10.investedUnderlyingBalance() == ((50/100 * 50000000) * (1 + 10/100)) + (50/100 * 50000000)

def test_hard_work_multiple_strategies(fund_through_proxy, accounts, token, profit_strategy_10, profit_strategy_50):
    token.mint(accounts[3], 100000000, {'from': accounts[0]})
    token.approve(fund_through_proxy, 50000000, {'from': accounts[3]})
    fund_through_proxy.deposit(50000000, {'from': accounts[3]})

    token.grantRole(brownie.web3.keccak(text="MINTER_ROLE"), profit_strategy_10, {'from': accounts[0]})
    fund_through_proxy.addStrategy(profit_strategy_10, 5000, 500, {'from': accounts[1]})
    token.grantRole(brownie.web3.keccak(text="MINTER_ROLE"), profit_strategy_50, {'from': accounts[0]})
    fund_through_proxy.addStrategy(profit_strategy_50, 2000, 500, {'from': accounts[1]})

    fund_through_proxy.doHardWork({'from': accounts[1]})
    profit_strategy_10.investAllUnderlying({'from': accounts[0]})
    profit_strategy_50.investAllUnderlying({'from': accounts[0]})

    assert profit_strategy_10.investedUnderlyingBalance() == (50/100 * 50000000) * (1 + 10/100)
    assert profit_strategy_50.investedUnderlyingBalance() == (20/100 * 50000000) * (1 + 50/100)
    assert fund_through_proxy.getPricePerShare() == fund_through_proxy.underlyingUnit() * (((50/100 * 50000000) * (1 + 10/100)) + ((20/100 * 50000000) * (1 + 50/100)) + (30/100 * 50000000)) / 50000000

def test_remove_strategy_after_hard_work_multiple_strategies(fund_through_proxy, accounts, token, profit_strategy_10, profit_strategy_50):
    token.mint(accounts[3], 100000000, {'from': accounts[0]})
    token.approve(fund_through_proxy, 50000000, {'from': accounts[3]})
    fund_through_proxy.deposit(50000000, {'from': accounts[3]})

    token.grantRole(brownie.web3.keccak(text="MINTER_ROLE"), profit_strategy_10, {'from': accounts[0]})
    fund_through_proxy.addStrategy(profit_strategy_10, 5000, 500, {'from': accounts[1]})
    token.grantRole(brownie.web3.keccak(text="MINTER_ROLE"), profit_strategy_50, {'from': accounts[0]})
    fund_through_proxy.addStrategy(profit_strategy_50, 2000, 500, {'from': accounts[1]})

    fund_through_proxy.doHardWork({'from': accounts[1]})
    profit_strategy_10.investAllUnderlying({'from': accounts[0]})
    profit_strategy_50.investAllUnderlying({'from': accounts[0]})

    assert profit_strategy_10.investedUnderlyingBalance() == (50/100 * 50000000) * (1 + 10/100)
    assert profit_strategy_50.investedUnderlyingBalance() == (20/100 * 50000000) * (1 + 50/100)
    assert fund_through_proxy.getPricePerShare() == fund_through_proxy.underlyingUnit() * (((50/100 * 50000000) * (1 + 10/100)) + ((20/100 * 50000000) * (1 + 50/100)) + (30/100 * 50000000)) / 50000000

    fund_through_proxy.removeStrategy(profit_strategy_50, {'from': accounts[0]})
    assert profit_strategy_50.investedUnderlyingBalance() == 0

def test_hard_work_single_strategy_rewards_event_fires(fund_through_proxy, accounts, token, profit_strategy_10):
    token.mint(accounts[3], 100000000, {'from': accounts[0]})
    token.approve(fund_through_proxy, 50000000, {'from': accounts[3]})
    fund_through_proxy.deposit(50000000, {'from': accounts[3]})

    token.grantRole(brownie.web3.keccak(text="MINTER_ROLE"), profit_strategy_10, {'from': accounts[0]})
    fund_through_proxy.addStrategy(profit_strategy_10, 5000, 500, {'from': accounts[1]})

    tx = fund_through_proxy.doHardWork({'from': accounts[1]})
    profit_strategy_10.investAllUnderlying({'from': accounts[0]})

    assert profit_strategy_10.investedUnderlyingBalance() == (50/100 * 50000000) * (1 + 10/100)
    assert fund_through_proxy.getPricePerShare() == fund_through_proxy.underlyingUnit() * (((50/100 * 50000000) * (1 + 10/100)) + (50/100 * 50000000)) / 50000000
    # assert tx.events["StrategyRewards"].values() == [profit_strategy_10, 0, 0]  ## zero profit for first hard work

    token.approve(fund_through_proxy, 50000000, {'from': accounts[3]})
    fund_through_proxy.deposit(50000000, {'from': accounts[3]})

    price_per_share = fund_through_proxy.getPricePerShare() / (10 ** fund_through_proxy.decimals())
    
    tx = fund_through_proxy.doHardWork({'from': accounts[1]})
    expected_profit = (50/100 * 50000000) * (10/100)
    expected_strategy_creator_fee = expected_profit * (500/10000) / price_per_share
    assert tx.events["StrategyRewards"].values() == [profit_strategy_10, expected_profit, expected_strategy_creator_fee]

def test_hard_work_single_strategy_creator_fee_to_account(fund_through_proxy, accounts, token, profit_strategy_10):
    token.mint(accounts[3], 100000000, {'from': accounts[0]})
    token.approve(fund_through_proxy, 50000000, {'from': accounts[3]})
    fund_through_proxy.deposit(50000000, {'from': accounts[3]})

    token.grantRole(brownie.web3.keccak(text="MINTER_ROLE"), profit_strategy_10, {'from': accounts[0]})
    fund_through_proxy.addStrategy(profit_strategy_10, 5000, 500, {'from': accounts[1]})

    tx = fund_through_proxy.doHardWork({'from': accounts[1]})
    profit_strategy_10.investAllUnderlying({'from': accounts[0]})

    token.approve(fund_through_proxy, 50000000, {'from': accounts[3]})
    fund_through_proxy.deposit(50000000, {'from': accounts[3]})

    price_per_share = fund_through_proxy.getPricePerShare() / (10 ** fund_through_proxy.decimals())
    
    tx = fund_through_proxy.doHardWork({'from': accounts[1]})   ## zero profit for first hard work, run again to test
    expected_profit = (50/100 * 50000000) * (10/100)
    expected_strategy_creator_fee = expected_profit * (500/10000) / price_per_share
    assert fund_through_proxy.balanceOf(accounts[0]) == expected_strategy_creator_fee

def test_hard_work_single_strategy_creator_fee_fund_fee_to_account(fund_through_proxy, accounts, token, profit_strategy_10):
    token.mint(accounts[3], 100000000, {'from': accounts[0]})
    token.approve(fund_through_proxy, 50000000, {'from': accounts[3]})
    fund_through_proxy.deposit(50000000, {'from': accounts[3]})

    token.grantRole(brownie.web3.keccak(text="MINTER_ROLE"), profit_strategy_10, {'from': accounts[0]})
    fund_through_proxy.addStrategy(profit_strategy_10, 5000, 500, {'from': accounts[1]})
    fund_through_proxy.setPerformanceFeeFund(500, {'from': accounts[1]})

    tx = fund_through_proxy.doHardWork({'from': accounts[1]})
    profit_strategy_10.investAllUnderlying({'from': accounts[0]})

    token.approve(fund_through_proxy, 50000000, {'from': accounts[3]})
    fund_through_proxy.deposit(50000000, {'from': accounts[3]})

    price_per_share = fund_through_proxy.getPricePerShare() / (10 ** fund_through_proxy.decimals())

    tx = fund_through_proxy.doHardWork({'from': accounts[1]})   ## zero profit for first hard work, run again to test
    expected_profit = (50/100 * 50000000) * (10/100)
    expected_strategy_creator_fee_in_underlying = expected_profit * (500/10000)
    expected_strategy_creator_fee = expected_strategy_creator_fee_in_underlying / price_per_share
    expected_fund_performance_fee = (expected_profit - expected_strategy_creator_fee_in_underlying) * (500/10000) / price_per_share
    assert float(fund_through_proxy.balanceOf(accounts[0])) == pytest.approx(expected_strategy_creator_fee, rel=1e-5)
    assert [float(i) for i in tx.events["FundManagerRewards"].values()] == pytest.approx([expected_profit - expected_strategy_creator_fee_in_underlying, expected_fund_performance_fee], rel=1e-4)

def test_hard_work_single_strategy_creator_fee_fund_fee_platform_fee_to_account(chain, fund_through_proxy, accounts, token, profit_strategy_10):
    token.mint(accounts[3], 100000000, {'from': accounts[0]})
    token.approve(fund_through_proxy, 50000000, {'from': accounts[3]})
    fund_through_proxy.deposit(50000000, {'from': accounts[3]})

    token.grantRole(brownie.web3.keccak(text="MINTER_ROLE"), profit_strategy_10, {'from': accounts[0]})
    fund_through_proxy.addStrategy(profit_strategy_10, 5000, 500, {'from': accounts[1]})
    fund_through_proxy.setPerformanceFeeFund(500, {'from': accounts[1]})
    fund_through_proxy.setPlatformFee(100, {'from': accounts[0]})

    tx = fund_through_proxy.doHardWork({'from': accounts[1]})
    profit_strategy_10.investAllUnderlying({'from': accounts[0]})

    token.approve(fund_through_proxy, 50000000, {'from': accounts[3]})
    fund_through_proxy.deposit(50000000, {'from': accounts[3]})

    chain.mine(timedelta=1000)
    price_per_share = fund_through_proxy.getPricePerShare() / (10 ** fund_through_proxy.decimals())

    tx = fund_through_proxy.doHardWork({'from': accounts[1]})   ## zero profit for first hard work, run again to test
    expected_profit = (50/100 * 50000000) * (10/100)
    expected_strategy_creator_fee_in_underlying = expected_profit * (500/10000)
    expected_strategy_creator_fee = expected_strategy_creator_fee_in_underlying / price_per_share
    expected_fund_performance_fee = (expected_profit - expected_strategy_creator_fee_in_underlying) * (500/10000) / price_per_share  ## goes to fund manager
    expected_platform_fee = 7 / price_per_share
    assert float(fund_through_proxy.balanceOf(accounts[0])) == pytest.approx(expected_strategy_creator_fee + expected_platform_fee, rel=1e-5)
    assert [float(v) for v in tx.events["PlatformRewards"].values()] == [50/100 * 50000000, pytest.approx(1000, abs=5), pytest.approx(7, abs=1)]


def test_hard_work_single_strategy_creator_fee_fund_fee_platform_fee_to_new_rewards_account(chain, fund_through_proxy, accounts, token, profit_strategy_10):
    token.mint(accounts[3], 100000000, {'from': accounts[0]})
    token.approve(fund_through_proxy, 50000000, {'from': accounts[3]})
    fund_through_proxy.deposit(50000000, {'from': accounts[3]})

    token.grantRole(brownie.web3.keccak(text="MINTER_ROLE"), profit_strategy_10, {'from': accounts[0]})
    fund_through_proxy.addStrategy(profit_strategy_10, 5000, 500, {'from': accounts[1]})
    fund_through_proxy.setPerformanceFeeFund(500, {'from': accounts[1]})
    fund_through_proxy.setPlatformFee(100, {'from': accounts[0]})
    fund_through_proxy.setPlatformRewards(accounts[5], {'from': accounts[0]})

    tx = fund_through_proxy.doHardWork({'from': accounts[1]})
    profit_strategy_10.investAllUnderlying({'from': accounts[0]})

    token.approve(fund_through_proxy, 50000000, {'from': accounts[3]})
    fund_through_proxy.deposit(50000000, {'from': accounts[3]})

    chain.mine(timedelta=1000)
    price_per_share = fund_through_proxy.getPricePerShare() / (10 ** fund_through_proxy.decimals())

    tx = fund_through_proxy.doHardWork({'from': accounts[1]})   ## zero profit for first hard work, run again to test
    expected_profit = (50/100 * 50000000) * (10/100)
    expected_strategy_creator_fee_in_underlying = expected_profit * (500/10000)
    expected_strategy_creator_fee = expected_strategy_creator_fee_in_underlying / price_per_share
    expected_fund_performance_fee = (expected_profit - expected_strategy_creator_fee_in_underlying) * (500/10000) / price_per_share
    assert fund_through_proxy.balanceOf(accounts[0]) == expected_strategy_creator_fee
    assert float(fund_through_proxy.balanceOf(accounts[1])) == pytest.approx(expected_fund_performance_fee, rel=1e-4)
    expected_platform_fee = 7 / price_per_share
    assert fund_through_proxy.balanceOf(accounts[5]) >= expected_platform_fee  ## Accounts for any dust


def test_rebalance_single_strategy_weight_change(fund_through_proxy, accounts, token, profit_strategy_10):
    token.mint(accounts[3], 100000000, {'from': accounts[0]})
    token.approve(fund_through_proxy, 50000000, {'from': accounts[3]})
    fund_through_proxy.deposit(50000000, {'from': accounts[3]})

    token.grantRole(brownie.web3.keccak(text="MINTER_ROLE"), profit_strategy_10, {'from': accounts[0]})
    fund_through_proxy.addStrategy(profit_strategy_10, 5000, 500, {'from': accounts[1]})

    fund_through_proxy.doHardWork({'from': accounts[1]})
    # profit_strategy_10.investAllUnderlying({'from': accounts[0]})  // No profit for easy testing
    assert profit_strategy_10.investedUnderlyingBalance() == (50/100 * 50000000)
    
    fund_through_proxy.updateStrategyWeightage(profit_strategy_10, 6000, {'from': accounts[1]})
    fund_through_proxy.doHardWork({'from': accounts[1]})

    assert profit_strategy_10.investedUnderlyingBalance() == (60/100 * 50000000)


def test_rebalance_single_strategy_manual(fund_through_proxy, accounts, token, profit_strategy_10):
    token.mint(accounts[3], 100000000, {'from': accounts[0]})
    token.approve(fund_through_proxy, 50000000, {'from': accounts[3]})
    fund_through_proxy.deposit(50000000, {'from': accounts[3]})

    token.grantRole(brownie.web3.keccak(text="MINTER_ROLE"), profit_strategy_10, {'from': accounts[0]})
    fund_through_proxy.addStrategy(profit_strategy_10, 5000, 500, {'from': accounts[1]})

    fund_through_proxy.doHardWork({'from': accounts[1]})
    profit_strategy_10.investAllUnderlying({'from': accounts[0]})
    fund_through_proxy.setShouldRebalance(True, {'from': accounts[1]})

    assert profit_strategy_10.investedUnderlyingBalance() == (50/100 * (1 + 10/100) * 50000000)


# def test_rebalance_multiple_strategies(fund_through_proxy, accounts, token, profit_strategy_10, profit_strategy_50):
#     token.mint(accounts[3], 100000000, {'from': accounts[0]})
#     token.approve(fund_through_proxy, 50000000, {'from': accounts[3]})
#     fund_through_proxy.deposit(50000000, {'from': accounts[3]})

#     token.grantRole(brownie.web3.keccak(text="MINTER_ROLE"), profit_strategy_10, {'from': accounts[0]})
#     fund_through_proxy.addStrategy(profit_strategy_10, 5000, 500, {'from': accounts[1]})
#     token.grantRole(brownie.web3.keccak(text="MINTER_ROLE"), profit_strategy_50, {'from': accounts[0]})
#     fund_through_proxy.addStrategy(profit_strategy_50, 2000, 500, {'from': accounts[1]})

#     fund_through_proxy.doHardWork({'from': accounts[1]})
#     # profit_strategy_10.investAllUnderlying({'from': accounts[0]})  // No profit for easy testing
#     fund_through_proxy.updateStrategyWeightage(profit_strategy_10, 7000, {'from': accounts[0]})
#     fund_through_proxy.updateStrategyWeightage(profit_strategy_50, 1000, {'from': accounts[0]})
#     fund_through_proxy.rebalance({'from': accounts[0]})

#     assert profit_strategy_10.investedUnderlyingBalance() == (70/100 * 50000000)
#     assert profit_strategy_50.investedUnderlyingBalance() == (10/100 * 50000000)
