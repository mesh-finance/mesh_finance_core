#!/usr/bin/python3

import pytest, brownie


@pytest.fixture(scope="function", autouse=True)
def isolate(fn_isolation):
    # perform a chain rewind after completing each test, to ensure proper isolation
    # https://eth-brownie.readthedocs.io/en/v1.10.3/tests-pytest-intro.html#isolation-fixtures
    pass

@pytest.fixture(scope="module")
def token(Token, accounts):
    return Token.deploy("Stable Token", "STAB", 18, {'from': accounts[0]})

@pytest.fixture(scope="module")
def token_2(Token, accounts):
    return Token.deploy("Stable Token 2", "STAB2", 18, {'from': accounts[0]})

@pytest.fixture(scope="module")
def fund(Fund, accounts):
    return Fund.deploy({'from': accounts[0]})

@pytest.fixture(scope="module")
def fund_2(Fund, accounts):
    return Fund.deploy({'from': accounts[0]})

@pytest.fixture(scope="module")
def governable(Governable, accounts):
    governance = Governable.deploy({'from': accounts[0]})
    governance.initializeGovernance(accounts[1], {'from': accounts[0]})
    return governance

@pytest.fixture(scope="module")
def fund_factory(FundFactory, accounts):
    fund_factory = FundFactory.deploy({'from': accounts[0]})
    return fund_factory

@pytest.fixture(scope="module")
def fund_proxy(fund_factory, fund, token, accounts):
    fund_name = "Mudrex Generic Fund"
    fund_symbol = "MDXGF"
    tx = fund_factory.createFund(fund, token, fund_name, fund_symbol, {'from': accounts[0]})
    fund_proxy = brownie.FundProxy.at(tx.new_contracts[0])
    return fund_proxy

@pytest.fixture(scope="module")
def fund_through_proxy(fund_factory, fund, token, accounts):
    fund_name = "Mudrex Generic Fund"
    fund_symbol = "MDXGF"
    tx = fund_factory.createFund(fund, token, fund_name, fund_symbol, {'from': accounts[0]})
    fund_through_proxy = brownie.Fund.at(tx.new_contracts[0])
    fund_through_proxy.setFundManager(accounts[1], {'from': accounts[0]})
    fund_through_proxy.setRelayer(accounts[3], {'from': accounts[1]})
    return fund_through_proxy

@pytest.fixture(scope="module")
def profit_strategy_10(ProfitStrategy, fund_through_proxy, accounts):
    return ProfitStrategy.deploy(fund_through_proxy, 1000, {'from': accounts[0]})

@pytest.fixture(scope="module")
def profit_strategy_50(ProfitStrategy, fund_through_proxy, accounts):
    return ProfitStrategy.deploy(fund_through_proxy, 5000, {'from': accounts[0]})

@pytest.fixture(scope="module")
def profit_strategy_80(ProfitStrategy, fund_through_proxy, accounts):
    return ProfitStrategy.deploy(fund_through_proxy, 8000, {'from': accounts[0]})

@pytest.fixture(scope="module")
def profit_strategy_10_fund_2(ProfitStrategy, fund_2, accounts):
    return ProfitStrategy.deploy(fund_2, 1000, {'from': accounts[0]})

@pytest.fixture(scope="module")
def connected_network():
    return brownie.network.show_active()

@pytest.fixture(scope="module")
def usdc(interface, connected_network):
    if (connected_network == "mainnet-fork"):
        return interface.ERC20("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48")
    elif (connected_network == "matic-fork"):
        return interface.ERC20("0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174")

@pytest.fixture(scope="module")
def test_usdc_account(accounts, connected_network):
    if (connected_network == "mainnet-fork"):
        return accounts.at("0x47ac0fb4f2d84898e4d9e7b4dab3c24507a6d503",force=True)
    elif (connected_network == "matic-fork"):
        return accounts.at("0xa80191Fca50BE00f8952c69232c93D57eeaCaf6f",force=True)

@pytest.fixture(scope="module")
def fund_through_proxy_usdc(fund_factory, fund, usdc, accounts):
    fund_name = "Mudrex High Risk Fund USDC"
    fund_symbol = "MESH_HR_USDC"
    tx = fund_factory.createFund(fund, usdc.address, fund_name, fund_symbol, {'from': accounts[0]})
    fund_usdc_through_proxy = brownie.Fund.at(tx.new_contracts[0])
    return fund_usdc_through_proxy