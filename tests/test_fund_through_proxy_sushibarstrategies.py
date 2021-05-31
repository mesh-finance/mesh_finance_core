#!/usr/bin/python3

import pytest, brownie

def test_sushibarstrategy_initialization(fund_sushi_through_proxy, profit_sushibarstrategy,sushi):
    assert profit_sushibarstrategy.fund() == fund_sushi_through_proxy
    assert profit_sushibarstrategy.underlying() == sushi.address

def test_add_strategy_two_sushibarstrategies(fund_sushi_through_proxy, accounts, profit_sushibarstrategy):
    fund_sushi_through_proxy.addStrategy(profit_sushibarstrategy, 5000, 500, {'from': accounts[0]})
    with brownie.reverts("This strategy is already active in this fund"):
        fund_sushi_through_proxy.addStrategy(profit_sushibarstrategy, 2000, 500, {'from': accounts[0]})

def test_sushibar_hard_work_single_strategy(fund_sushi_through_proxy, accounts, sushi,sushi_holder, profit_sushibarstrategy):

    sushi.transfer(fund_sushi_through_proxy,100000,{'from': sushi_holder})

    fund_sushi_through_proxy.addStrategy(profit_sushibarstrategy, 5000, 0, {'from': accounts[0]})
    
    tx = fund_sushi_through_proxy.doHardWork({'from': accounts[0]})
    profit_sushibarstrategy.doHardWork({'from': accounts[0]})

    assert fund_sushi_through_proxy.totalValueLocked() == 87544 
    assert profit_sushibarstrategy.investedUnderlyingBalance() == 37544
    assert fund_sushi_through_proxy.underlying() == sushi.address

    assert tx.events["HardWorkDone"].values() == [87544, fund_sushi_through_proxy.underlyingUnit()]