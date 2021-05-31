#!/usr/bin/python3

import pytest, brownie

def test_bentoboxstrategy_initialization(fund_usdc_through_proxy, profit_bentoboxstrategy, usdc):
    assert profit_bentoboxstrategy.fund() == fund_usdc_through_proxy
    assert profit_bentoboxstrategy.underlying() == usdc.address

def test_add_strategy_two_bentoboxstrategies(fund_usdc_through_proxy, accounts, profit_bentoboxstrategy):
    fund_usdc_through_proxy.addStrategy(profit_bentoboxstrategy, 5000, 500, {'from': accounts[0]})
    with brownie.reverts("This strategy is already active in this fund"):
        fund_usdc_through_proxy.addStrategy(profit_bentoboxstrategy, 2000, 500, {'from': accounts[0]})

def test_bentobox_hard_work_single_strategy(fund_usdc_through_proxy, accounts, usdc,usdc_holder, profit_bentoboxstrategy):

    usdc.transfer(fund_usdc_through_proxy,100000,{'from': usdc_holder})

    fund_usdc_through_proxy.addStrategy(profit_bentoboxstrategy, 5000, 0, {'from': accounts[0]})
    
    #tx = fund_usdc_through_proxy.doHardWork({'from': accounts[0]})
    profit_bentoboxstrategy.doHardWork({'from': accounts[0]})

    #assert fund_usdc_through_proxy.totalValueLocked() == 100000 - 1
    #assert profit_bentoboxstrategy.investedUnderlyingBalance() == 50000 - 1
    #assert fund_usdc_through_proxy.underlying() == usdc.address

    #assert tx.events["HardWorkDone"].values() == [100000 - 1, fund_usdc_through_proxy.underlyingUnit()]