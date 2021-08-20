#!/usr/bin/python3

import pytest, brownie

def test_withdrawal_without_any_deposit(fund_through_proxy, accounts):
    with brownie.reverts("Fund has no shares"):
        fund_through_proxy.withdraw(50, {'from': accounts[1]})

def test_withdrawal_without_any_deposit_from_account(fund_through_proxy, accounts, token):
    token.mint(accounts[1], 100, {'from': accounts[0]})
    token.approve(fund_through_proxy, 50, {'from': accounts[1]})
    fund_through_proxy.deposit(50, {'from': accounts[1]})
    with brownie.reverts('ERC20: burn amount exceeds balance'):
        fund_through_proxy.withdraw(50, {'from': accounts[2]})

def test_withdrawal_without_enough_shares(fund_through_proxy, accounts, token):
    token.mint(accounts[1], 100, {'from': accounts[0]})
    token.approve(fund_through_proxy, 50, {'from': accounts[1]})
    fund_through_proxy.deposit(50, {'from': accounts[1]})
    with brownie.reverts('ERC20: burn amount exceeds balance'):
        fund_through_proxy.withdraw(100, {'from': accounts[1]})

def test_withdrawal(fund_through_proxy, accounts, token):
    token.mint(accounts[1], 100, {'from': accounts[0]})
    token.approve(fund_through_proxy, 50, {'from': accounts[1]})
    fund_through_proxy.deposit(50, {'from': accounts[1]})
    
    assert fund_through_proxy.balanceOf(accounts[1]) == 50   ## zero shares initially, so same amount minted as deposit

    tx = fund_through_proxy.withdraw(50, {'from': accounts[1]})

    assert fund_through_proxy.balanceOf(accounts[1]) == 0
    assert token.balanceOf(accounts[1]) == 100
    assert tx.events["Withdraw"].values() == [accounts[1], 50]

def test_withdrawal_with_deposits_paused(fund_through_proxy, accounts, token):
    token.mint(accounts[1], 100, {'from': accounts[0]})
    token.approve(fund_through_proxy, 50, {'from': accounts[1]})
    fund_through_proxy.deposit(50, {'from': accounts[1]})
    fund_through_proxy.pauseDeposits(True, {'from': accounts[0]})
    
    assert fund_through_proxy.balanceOf(accounts[1]) == 50   ## zero shares initially, so same amount minted as deposit

    fund_through_proxy.withdraw(50, {'from': accounts[1]})

    assert fund_through_proxy.balanceOf(accounts[1]) == 0
    assert token.balanceOf(accounts[1]) == 100


def test_large_withdrawal_after_hard_work(fund_through_proxy, accounts, token, profit_strategy_10, profit_strategy_50):
    token.mint(accounts[1], 10000000, {'from': accounts[0]})
    intial_balance_for_governance = token.balanceOf(accounts[0])
    intial_balance_for_account = token.balanceOf(accounts[1])
    token.approve(fund_through_proxy, 5000000, {'from': accounts[1]})
    fund_through_proxy.deposit(5000000, {'from': accounts[1]})

    token.grantRole(brownie.web3.keccak(text="MINTER_ROLE"), profit_strategy_10, {'from': accounts[0]})
    fund_through_proxy.addStrategy(profit_strategy_10, 5000, 500, {'from': accounts[1]})
    token.grantRole(brownie.web3.keccak(text="MINTER_ROLE"), profit_strategy_50, {'from': accounts[0]})
    fund_through_proxy.addStrategy(profit_strategy_50, 2000, 500, {'from': accounts[1]})

    fund_through_proxy.doHardWork({'from': accounts[1]})

    fund_through_proxy.withdraw(4000000, {'from': accounts[1]})

    assert fund_through_proxy.balanceOf(accounts[1]) == 1000000
    assert float(token.balanceOf(accounts[1])) == pytest.approx(9000000)
    assert token.balanceOf(fund_through_proxy) == 0
