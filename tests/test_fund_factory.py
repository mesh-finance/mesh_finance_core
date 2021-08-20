#!/usr/bin/python3

import pytest, brownie

fund_name = "Mudrex Generic Fund"
fund_symbol = "MDXGF"

def test_initialization(fund_factory, accounts):
    assert fund_factory.governance() == accounts[0]

def test_update_governance_from_non_governance_account(fund_factory, accounts):
    
    with brownie.reverts("Not governance"):
        fund_factory.updateGovernance(accounts[2], {'from': accounts[1]})

def test_update_governance_zero_account(fund_factory, accounts):

    zero_account = accounts.at("0x0000000000000000000000000000000000000000",force=True)
    
    with brownie.reverts("new governance shouldn't be empty"):
        fund_factory.updateGovernance(zero_account, {'from': accounts[0]})

def test_update_governance_accept_from_wrong_account(fund_factory, accounts):
    fund_factory.updateGovernance(accounts[2], {'from': accounts[0]})
    
    with brownie.reverts():
        fund_factory.acceptGovernance({'from': accounts[1]})

def test_update_governance_and_accept(fund_factory, accounts):
    fund_factory.updateGovernance(accounts[2], {'from': accounts[0]})
    tx = fund_factory.acceptGovernance({'from': accounts[2]})
    
    assert fund_factory.governance() == accounts[2]
    assert tx.events["GovernanceUpdated"].values() == [accounts[2], accounts[0]]

def test_create_fund_from_non_fund_implementation(fund_factory, accounts, token):
    
    with brownie.reverts():
        fund_factory.createFund(accounts[1], token, fund_name, fund_symbol, {'from': accounts[0]})

def test_create_fund_from_non_governance_account(fund_factory, accounts, fund, token):
    
    with brownie.reverts("Not governance"):
        fund_factory.createFund(fund, token, fund_name, fund_symbol, {'from': accounts[1]})

def test_create_fund(fund_factory, accounts, fund, token):
    tx = fund_factory.createFund(fund, token, fund_name, fund_symbol, {'from': accounts[0]})
    fund_proxy = brownie.FundProxy.at(tx.new_contracts[0])
    
    assert fund_proxy.implementation() == fund

def test_created_fund_through_proxy(fund_factory, accounts, fund, token):
    tx = fund_factory.createFund(fund, token, fund_name, fund_symbol, {'from': accounts[0]})
    fund_through_proxy = brownie.Fund.at(tx.new_contracts[0])
    
    assert fund_through_proxy.decimals() == token.decimals()
    assert fund_through_proxy.symbol() == fund_symbol
    assert fund_through_proxy.name() == fund_name

def test_new_fund_event_fires(fund_factory, accounts, fund, token):
    tx = fund_factory.createFund(fund, token, fund_name, fund_symbol, {'from': accounts[0]})
    fund_proxy = brownie.FundProxy.at(tx.new_contracts[0])

    assert len(tx.events) == 1
    assert tx.events["NewFund"].values() == [fund_proxy]
