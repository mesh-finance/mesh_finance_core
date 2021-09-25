#!/usr/bin/python3

import pytest, brownie

strategy_weightage = 8000

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_deployment(CompoundLendingStrategyMainnetUSDC, interface, fund_through_proxy_usdc, usdc, accounts):
    compound_strat = CompoundLendingStrategyMainnetUSDC.deploy(fund_through_proxy_usdc, {'from': accounts[0]})
    cToken_address = compound_strat.cToken()
    cToken = interface.ICToken(cToken_address)
    assert compound_strat.name() == "CompoundLendingStrategyMainnetUSDC"
    assert compound_strat.version() == "V1"
    assert cToken.underlying() == usdc

@pytest.fixture
def compound_strat(CompoundLendingStrategyMainnetUSDC, fund_through_proxy_usdc, usdc, accounts):
    return CompoundLendingStrategyMainnetUSDC.deploy(fund_through_proxy_usdc, {'from': accounts[0]})


@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_add_strategy(compound_strat, fund_through_proxy_usdc, usdc, accounts):

    required_fund = fund_through_proxy_usdc
    
    tx = required_fund.addStrategy(compound_strat, strategy_weightage, 0, {'from': accounts[1]})

    assert required_fund.getStrategyList() == [compound_strat]
    assert required_fund.getStrategy(compound_strat)[0] == strategy_weightage
    assert required_fund.getStrategy(compound_strat)[1] == 0
    assert tx.events["StrategyAdded"].values() == [compound_strat, strategy_weightage, 0]

@pytest.fixture
def fund_through_proxy_usdc_with_strategy_and_deposit(fund_through_proxy_usdc, compound_strat, usdc, test_usdc_account, accounts):
    required_fund = fund_through_proxy_usdc
    tx = required_fund.addStrategy(compound_strat, strategy_weightage, 0, {'from': accounts[1]})
    
    amount_to_deposit = 1000 * (10 ** usdc.decimals())
    usdc.approve(required_fund, amount_to_deposit, {'from': test_usdc_account})
    tx = required_fund.deposit(amount_to_deposit, {'from': test_usdc_account})

    return required_fund

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_hard_work(fund_through_proxy_usdc_with_strategy_and_deposit, compound_strat, interface, usdc, accounts):

    required_fund = fund_through_proxy_usdc_with_strategy_and_deposit
    
    assert compound_strat.investedUnderlyingBalance() == 0

    amount_deposited = 1000 * (10 ** usdc.decimals())
    tx = required_fund.doHardWork({'from': accounts[1]})
    
    cToken_address = compound_strat.cToken()
    cToken = interface.ICToken(cToken_address)
    ctoken_price_per_share = cToken.exchangeRateStored()

    expected_tvl = amount_deposited
    expected_price_per_share = 10 ** required_fund.decimals()

    expected_underlying_balance = amount_deposited * strategy_weightage/10000

    assert float(compound_strat.investedUnderlyingBalance()) == pytest.approx(expected_underlying_balance)
    assert float(required_fund.getPricePerShare()) == pytest.approx(expected_price_per_share)
    assert [float(v) for v in tx.events["HardWorkDone"].values()] == pytest.approx([expected_tvl, expected_price_per_share])
    assert cToken.balanceOf(compound_strat) == (expected_underlying_balance / ctoken_price_per_share) * (10 ** 18)

@pytest.fixture
def fund_through_proxy_usdc_after_hardwork(fund_through_proxy_usdc_with_strategy_and_deposit, accounts):
    
    tx = fund_through_proxy_usdc_with_strategy_and_deposit.doHardWork({'from': accounts[1]})
    
    return fund_through_proxy_usdc_with_strategy_and_deposit


@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_withdraw_small(fund_through_proxy_usdc_after_hardwork, compound_strat, usdc, test_usdc_account):
    
    required_fund = fund_through_proxy_usdc_after_hardwork
    shares_to_withdraw = 100 * (10 ** required_fund.decimals())
    price_per_share = required_fund.getPricePerShare()
    amount_to_withdraw = shares_to_withdraw * price_per_share / (10 ** required_fund.decimals())

    fund_balance_before = required_fund.balanceOf(test_usdc_account)
    usdc_balance_before = usdc.balanceOf(test_usdc_account)
    usdc_in_fund_before = usdc.balanceOf(required_fund)
    strategy_balance_before = compound_strat.investedUnderlyingBalance()

    tx = required_fund.withdraw(shares_to_withdraw, {'from': test_usdc_account})

    fund_balance_after = required_fund.balanceOf(test_usdc_account)
    usdc_balance_after = usdc.balanceOf(test_usdc_account)
    usdc_in_fund_after = usdc.balanceOf(required_fund)
    strategy_balance_after = compound_strat.investedUnderlyingBalance()

    assert fund_balance_before - fund_balance_after == shares_to_withdraw
    assert float(usdc_balance_after - usdc_balance_before) == pytest.approx(amount_to_withdraw)
    assert float(usdc_in_fund_before - usdc_in_fund_after) == pytest.approx(amount_to_withdraw)
    assert float(strategy_balance_after) == pytest.approx(strategy_balance_before)


@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_withdraw_large(fund_through_proxy_usdc_after_hardwork, compound_strat, usdc, test_usdc_account):
    
    required_fund = fund_through_proxy_usdc_after_hardwork
    shares_to_withdraw = 500 * (10 ** required_fund.decimals())
    price_per_share = required_fund.getPricePerShare()
    amount_to_withdraw = shares_to_withdraw * price_per_share / (10 ** required_fund.decimals())

    fund_balance_before = required_fund.balanceOf(test_usdc_account)
    usdc_balance_before = usdc.balanceOf(test_usdc_account)
    usdc_in_fund_before = usdc.balanceOf(required_fund)
    strategy_balance_before = compound_strat.investedUnderlyingBalance()

    tx = required_fund.withdraw(shares_to_withdraw, {'from': test_usdc_account})

    fund_balance_after = required_fund.balanceOf(test_usdc_account)
    usdc_balance_after = usdc.balanceOf(test_usdc_account)
    usdc_in_fund_after = usdc.balanceOf(required_fund)
    strategy_balance_after = compound_strat.investedUnderlyingBalance()

    assert fund_balance_before - fund_balance_after == shares_to_withdraw
    assert float(usdc_balance_after - usdc_balance_before) == pytest.approx(amount_to_withdraw, rel=1e-3)
    assert usdc_in_fund_after == 0
    assert float(strategy_balance_before - strategy_balance_after) == pytest.approx(amount_to_withdraw - usdc_in_fund_before, rel=1e-3)


@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_remove_strategy(fund_through_proxy_usdc_after_hardwork, compound_strat, usdc, accounts):

    required_fund = fund_through_proxy_usdc_after_hardwork
    total_value_locked_before = required_fund.totalValueLocked()
    strategy_balance_before = compound_strat.investedUnderlyingBalance()

    tx = required_fund.removeStrategy(compound_strat, {'from': accounts[1]})

    total_value_locked_after = required_fund.totalValueLocked()
    strategy_balance_after = compound_strat.investedUnderlyingBalance()

    assert required_fund.getStrategyList() == []
    assert tx.events["StrategyRemoved"].values() == [compound_strat]
    assert float(total_value_locked_before) == pytest.approx(total_value_locked_after)
    assert strategy_balance_after == 0

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_hardwork_with_invest_activate_false(fund_through_proxy_usdc_with_strategy_and_deposit, compound_strat, usdc, accounts, interface):
    cToken_address = compound_strat.cToken()
    cToken = interface.ICToken(cToken_address)
    ctoken_balance_before = cToken.balanceOf(compound_strat)
    compound_strat.setInvestActivated(False, {'from': accounts[0]})
    underlying_balance_before = usdc.balanceOf(compound_strat)
    fund_through_proxy_usdc_with_strategy_and_deposit.doHardWork({'from': accounts[1]})
    underlying_balance_after = usdc.balanceOf(compound_strat)
    ctoken_balance_after = cToken.balanceOf(compound_strat)
    assert underlying_balance_after >= underlying_balance_before
    assert ctoken_balance_after == ctoken_balance_before

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_set_invest_activate_with_random_address(fund_through_proxy_usdc_with_strategy_and_deposit, compound_strat, usdc, accounts, interface):
    with brownie.reverts("The sender has to be the governance or fund manager"):
        compound_strat.setInvestActivated(False, {'from': accounts[7]})

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_partial_withdraw_shares_with_random_address(fund_through_proxy_usdc_after_hardwork, compound_strat, accounts, interface):
    cToken_address = compound_strat.cToken()
    cToken = interface.ICToken(cToken_address)
    ctoken_balance = cToken.balanceOf(compound_strat)
    ctokens_to_withdraw = ctoken_balance/4
    with brownie.reverts("The sender has to be the governance or fund manager"):
        compound_strat.withdrawPartialShares(ctokens_to_withdraw, {'from': accounts[7]})

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_partial_withdraw_shares_zero_shares(fund_through_proxy_usdc_after_hardwork, compound_strat, accounts):
    with brownie.reverts("Shares should be greater than 0"):
        compound_strat.withdrawPartialShares(0, {'from': accounts[0]})

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_partial_withdraw_shares(fund_through_proxy_usdc_after_hardwork, compound_strat, usdc, accounts, interface):
    cToken_address = compound_strat.cToken()
    cToken = interface.ICToken(cToken_address)
    underlying_balance_before = usdc.balanceOf(compound_strat)
    underlying_to_withdraw = 200 * (10 ** usdc.decimals())
    ctoken_price_per_share = cToken.exchangeRateStored()
    ctokens_to_withdraw = (underlying_to_withdraw / ctoken_price_per_share) * (10 ** 18)
    compound_strat.withdrawPartialShares(ctokens_to_withdraw, {'from': accounts[0]})
    underlying_balance_after = usdc.balanceOf(compound_strat)
    assert float(underlying_balance_after) == pytest.approx(underlying_to_withdraw + underlying_balance_before)

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_sweep_with_random_address(fund_through_proxy_usdc_after_hardwork, compound_strat, accounts, interface): 
    uni_token_address = "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984"
    random_uni_holder = "0x47173b170c64d16393a52e6c480b3ad8c302ba1e"
    interface.ERC20(uni_token_address).transfer(
        compound_strat,
        200 * (10 ** 18),
        {'from':random_uni_holder}
    )
    with brownie.reverts("Not governance"):
        compound_strat.sweep(uni_token_address, random_uni_holder, {'from': accounts[7]})

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_sweep_with_reward_tokens(fund_through_proxy_usdc_after_hardwork, compound_strat, accounts, interface): 
    reward_token_address = "0xc00e94Cb662C3520282E6f5717214004A7f26888"
    random_reward_token_holder = "0xD3F03984a90fd15E909B2E9467E98cADeA181da3"
    interface.ERC20(reward_token_address).transfer(
        compound_strat,
        200 * (10 ** 18),
        {'from':random_reward_token_holder}
    )
    with brownie.reverts("Token is restricted"):
        compound_strat.sweep(reward_token_address, random_reward_token_holder, {'from': accounts[0]})

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_sweep_with_uni_tokens(fund_through_proxy_usdc_after_hardwork, compound_strat, accounts, interface): 
    uni_token_address = "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984"
    random_uni_holder = "0x47173b170c64d16393a52e6c480b3ad8c302ba1e"
    interface.ERC20(uni_token_address).transfer(
        compound_strat,
        200 * (10 ** 18),
        {'from':random_uni_holder}
    )
    strategy_uni_balance_before = interface.ERC20(uni_token_address).balanceOf(compound_strat)
    compound_strat.sweep(uni_token_address, random_uni_holder, {'from': accounts[0]})
    strategy_uni_balance_after = interface.ERC20(uni_token_address).balanceOf(compound_strat)
    assert strategy_uni_balance_before != 0
    assert strategy_uni_balance_after == 0

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_claim_liquidate_reinvest_with_random_address(compound_strat, accounts, interface, chain):
    with brownie.reverts("The sender has to be the relayer or fund manager"):
        compound_strat.claimLiquidateAndReinvestRewards({'from':accounts[7]})

# TODO
# @pytest.mark.require_network("mainnet-fork", "hardhat-fork")
# def test_claim_reward_token(fund_through_proxy_usdc_after_hardwork, compound_strat, accounts, interface, chain):
#     reward_token_address = "0xc00e94Cb662C3520282E6f5717214004A7f26888"
#     reward_token_balance_before = interface.ERC20(reward_token_address).balanceOf(compound_strat)
#     chain.mine(1000)
#     compound_strat.claimRewards()
#     reward_token_balance_after = interface.ERC20(reward_token_address).balanceOf(compound_strat)
#     assert reward_token_balance_before == 0
#     assert reward_token_balance_after != 0

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_liquidate_without_claim_reward_tokens(fund_through_proxy_usdc_after_hardwork, compound_strat, accounts, interface): 
    reward_token_address = "0xc00e94Cb662C3520282E6f5717214004A7f26888"
    random_reward_token_holder = "0xD3F03984a90fd15E909B2E9467E98cADeA181da3"
    interface.ERC20(reward_token_address).transfer(
        compound_strat,
        200 * (10 ** interface.ERC20(reward_token_address).decimals()),
        {'from':random_reward_token_holder}
    )

    underlying_balance_before = compound_strat.investedUnderlyingBalance()
    compound_strat.claimLiquidateAndReinvestRewards({'from':accounts[1]})
    underlying_balance_after = compound_strat.investedUnderlyingBalance()

    assert underlying_balance_after > underlying_balance_before
