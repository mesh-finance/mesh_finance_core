#!/usr/bin/python3

import pytest, brownie
from brownie import FundProxy, Fund

def test_upgrade_fund_without_scheduling(fund_proxy, accounts, fund_2):
    
    with brownie.reverts("Upgrade not scheduled"):
        fund_proxy.upgrade(fund_2, {'from': accounts[1]})

def test_upgrade_fund_from_non_governance_account(fund_proxy, accounts, fund_2):
    fund_proxy_address = fund_proxy.address
    FundProxy.remove(fund_proxy)
    fund_through_proxy = Fund.at(fund_proxy_address)
    fund_through_proxy.scheduleUpgrade(fund_2, {'from': accounts[0]})

    Fund.remove(fund_through_proxy)
    fund_proxy = FundProxy.at(fund_proxy_address)
    
    with brownie.reverts("Issue when finalizing the upgrade"):
        fund_proxy.upgrade(fund_2, {'from': accounts[1]})

def test_upgrade_fund_wrong_implementation(fund_proxy, fund_through_proxy, accounts, fund_2, fund):
    fund_proxy_address = fund_proxy.address
    FundProxy.remove(fund_proxy)
    fund_through_proxy = Fund.at(fund_proxy_address)
    fund_through_proxy.scheduleUpgrade(fund, {'from': accounts[0]})

    Fund.remove(fund_through_proxy)
    fund_proxy = FundProxy.at(fund_proxy_address)
    
    with brownie.reverts("NewImplementation is not same"):
        fund_proxy.upgrade(fund_2, {'from': accounts[0]})

def test_upgrade_fund(fund_proxy, accounts, fund_2):
    fund_proxy_address = fund_proxy.address
    FundProxy.remove(fund_proxy)
    fund_through_proxy = Fund.at(fund_proxy_address)
    fund_through_proxy.scheduleUpgrade(fund_2, {'from': accounts[0]})

    Fund.remove(fund_through_proxy)
    fund_proxy = FundProxy.at(fund_proxy_address)
    
    fund_proxy.upgrade(fund_2, {'from': accounts[0]})
    
    assert fund_proxy.implementation() == fund_2

def test_changed_deposit_limit_after_upgrade(fund_proxy, accounts, fund_2):
    fund_proxy_address = fund_proxy.address
    FundProxy.remove(fund_proxy)
    fund_through_proxy = Fund.at(fund_proxy_address)
    fund_through_proxy.scheduleUpgrade(fund_2, {'from': accounts[0]})
    fund_through_proxy.setDepositLimit(10, {'from': accounts[0]})

    Fund.remove(fund_through_proxy)
    fund_proxy = FundProxy.at(fund_proxy_address)
    
    fund_proxy.upgrade(fund_2, {'from': accounts[0]})

    FundProxy.remove(fund_proxy)
    fund_through_proxy = Fund.at(fund_proxy_address)
    
    assert fund_through_proxy.depositLimit() == 10
