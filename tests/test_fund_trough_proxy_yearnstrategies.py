#!/usr/bin/python3

import pytest, brownie

def test_yearn_hard_work_single_strategy(fund_usdc_through_proxy, accounts, usdc,usdc_holder, profit_yearnstrategy):

    usdc.transfer(fund_usdc_through_proxy,100000,{'from': usdc_holder})

    fund_usdc_through_proxy.addStrategy(profit_yearnstrategy, 5000, 0, {'from': accounts[0]})
    
    tx = fund_usdc_through_proxy.doHardWork({'from': accounts[0]})
    profit_yearnstrategy.doHardWork({'from': accounts[0]})

    assert fund_usdc_through_proxy.totalValueLocked() == 100000 - 1
    assert profit_yearnstrategy.investedUnderlyingBalance() == 50000 - 1
    assert fund_usdc_through_proxy.underlying() == usdc.address

    assert tx.events["HardWorkDone"].values() == [100000 - 1, fund_usdc_through_proxy.underlyingUnit()]

def test_yearnstrategy_initialization(fund_usdc_through_proxy, profit_yearnstrategy, usdc):
    assert profit_yearnstrategy.fund() == fund_usdc_through_proxy
    assert profit_yearnstrategy.underlying() == usdc.address


def test_add_strategy_two_yearnstrategies(fund_usdc_through_proxy, accounts, profit_yearnstrategy):
    fund_usdc_through_proxy.addStrategy(profit_yearnstrategy, 5000, 500, {'from': accounts[0]})
    with brownie.reverts("This strategy is already active in this fund"):
        fund_usdc_through_proxy.addStrategy(profit_yearnstrategy, 2000, 500, {'from': accounts[0]})

def test_add_strategy_two_different_strategies(fund_usdc_through_proxy, accounts, profit_strategy_10, profit_yearnstrategy):
    fund_usdc_through_proxy.addStrategy(profit_yearnstrategy, 5000, 500, {'from': accounts[0]})
    with brownie.reverts("The strategy does not belong to this fund"):
        fund_usdc_through_proxy.addStrategy(profit_strategy_10, 5000, 500, {'from': accounts[0]})

def test_add_wrong_strategy(fund_through_proxy, accounts, profit_yearnstrategy):
    with brownie.reverts("The strategy does not belong to this fund"):
        fund_through_proxy.addStrategy(profit_yearnstrategy, 5000, 500, {'from': accounts[0]})

def test_deploy_strategy_wrong_token(fund_factory, fund, token, accounts,YearnV2StrategyUSDC):
    fund_name = "Mudrex Generic Fund"
    fund_symbol = "MDXGF"
    tx = fund_factory.createFund(fund, token, fund_name, fund_symbol, {'from': accounts[0]})
    fund_through_proxy = brownie.Fund.at(tx.new_contracts[0])
    with brownie.reverts("Underlying do not match"):
        YearnV2StrategyUSDC.deploy(fund_through_proxy, {'from': accounts[0]})

