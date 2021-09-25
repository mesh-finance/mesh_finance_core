#!/usr/bin/python3

import pytest, brownie

strategy_weightage = 8000

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_deployment(AaveV2LendingStrategyMainnet, interface, fund_through_proxy_usdc, usdc, accounts):
    aavev2strat = AaveV2LendingStrategyMainnet.deploy(fund_through_proxy_usdc, {'from': accounts[0]})
    assert aavev2strat.name() == "AaveV2LendingStrategyMainnet"
    assert aavev2strat.version() == "V1"
    assert aavev2strat.canNotSweep(usdc) == True

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_deployment_with_zero_address(AaveV2LendingStrategyMainnet, interface, zero_account, usdc, accounts):
    with brownie.reverts("Fund cannot be empty"):
        AaveV2LendingStrategyMainnet.deploy(zero_account, {'from': accounts[0]})

@pytest.fixture
def aavev2strat(AaveV2LendingStrategyMainnet, fund_through_proxy_usdc, accounts):
    return AaveV2LendingStrategyMainnet.deploy(fund_through_proxy_usdc, {'from': accounts[0]})

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_add_strategy(aavev2strat, fund_through_proxy_usdc, accounts):
    tx = fund_through_proxy_usdc.addStrategy(aavev2strat, strategy_weightage, 0, {'from': accounts[1]})
    assert fund_through_proxy_usdc.getStrategyList() == [aavev2strat]
    assert fund_through_proxy_usdc.getStrategy(aavev2strat)[0] == strategy_weightage
    assert fund_through_proxy_usdc.getStrategy(aavev2strat)[1] == 0
    assert tx.events["StrategyAdded"].values() == [aavev2strat, strategy_weightage, 0]

@pytest.fixture
def fund_through_proxy_usdc_with_strategy_and_deposit(fund_through_proxy_usdc, aavev2strat, usdc, test_usdc_account, accounts):
    tx = fund_through_proxy_usdc.addStrategy(aavev2strat, strategy_weightage, 0, {'from': accounts[1]})
    amount_to_deposit = 1000 * (10 ** usdc.decimals())
    usdc.approve(fund_through_proxy_usdc, amount_to_deposit, {'from': test_usdc_account})
    tx = fund_through_proxy_usdc.deposit(amount_to_deposit, {'from': test_usdc_account})
    return fund_through_proxy_usdc

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_hard_work(fund_through_proxy_usdc_with_strategy_and_deposit, aavev2strat, interface, usdc, accounts):

    assert aavev2strat.investedUnderlyingBalance() == 0

    amount_deposited = 1000 * (10 ** usdc.decimals())
    tx = fund_through_proxy_usdc_with_strategy_and_deposit.doHardWork({'from': accounts[1]})
    
    aToken = aavev2strat.aToken()

    expected_tvl = amount_deposited
    expected_price_per_share = 10 ** fund_through_proxy_usdc_with_strategy_and_deposit.decimals()

    expected_underlying_balance = amount_deposited * strategy_weightage/10000

    assert float(aavev2strat.investedUnderlyingBalance()) == pytest.approx(expected_underlying_balance)
    assert float(fund_through_proxy_usdc_with_strategy_and_deposit.getPricePerShare()) == pytest.approx(expected_price_per_share)
    assert [v for v in tx.events["HardWorkDone"].values()] == [expected_tvl, expected_price_per_share]
    assert interface.IERC20(aToken).balanceOf(aavev2strat) == expected_underlying_balance

@pytest.fixture
def fund_through_proxy_usdc_after_hardwork(fund_through_proxy_usdc_with_strategy_and_deposit, accounts):
    
    tx = fund_through_proxy_usdc_with_strategy_and_deposit.doHardWork({'from': accounts[1]})
    
    return fund_through_proxy_usdc_with_strategy_and_deposit

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_withdraw_small(fund_through_proxy_usdc_after_hardwork, aavev2strat, usdc, test_usdc_account, interface):
    
    shares_to_withdraw = 100 * (10 ** fund_through_proxy_usdc_after_hardwork.decimals())
    price_per_share = fund_through_proxy_usdc_after_hardwork.getPricePerShare()
    usdc_to_withdraw = shares_to_withdraw * price_per_share / (10 ** fund_through_proxy_usdc_after_hardwork.decimals())

    aToken = aavev2strat.aToken()

    fund_balance_before = fund_through_proxy_usdc_after_hardwork.balanceOf(test_usdc_account)
    usdc_balance_before = usdc.balanceOf(test_usdc_account)
    usdc_in_fund_before = usdc.balanceOf(fund_through_proxy_usdc_after_hardwork)
    strategy_balance_before = aavev2strat.investedUnderlyingBalance()
    strategy_balance_aToken_before = interface.IERC20(aToken).balanceOf(aavev2strat)

    fund_through_proxy_usdc_after_hardwork.withdraw(shares_to_withdraw, {'from': test_usdc_account})

    fund_balance_after = fund_through_proxy_usdc_after_hardwork.balanceOf(test_usdc_account)
    usdc_balance_after = usdc.balanceOf(test_usdc_account)
    usdc_in_fund_after = usdc.balanceOf(fund_through_proxy_usdc_after_hardwork)
    strategy_balance_after = aavev2strat.investedUnderlyingBalance()
    strategy_balance_aToken_after = interface.IERC20(aToken).balanceOf(aavev2strat)

    assert fund_balance_before - fund_balance_after == shares_to_withdraw
    assert float(usdc_balance_after - usdc_balance_before) == pytest.approx(usdc_to_withdraw)
    assert float(usdc_in_fund_before - usdc_in_fund_after) == pytest.approx(usdc_to_withdraw)
    assert float(strategy_balance_aToken_after) == pytest.approx(strategy_balance_aToken_before)
    assert float(strategy_balance_after) == pytest.approx(strategy_balance_before)

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_withdraw_large(fund_through_proxy_usdc_after_hardwork, aavev2strat, usdc, test_usdc_account):
    
    shares_to_withdraw = 500 * (10 ** fund_through_proxy_usdc_after_hardwork.decimals())
    price_per_share = fund_through_proxy_usdc_after_hardwork.getPricePerShare()
    amount_to_withdraw = shares_to_withdraw * price_per_share / (10 ** fund_through_proxy_usdc_after_hardwork.decimals())

    fund_balance_before = fund_through_proxy_usdc_after_hardwork.balanceOf(test_usdc_account)
    usdc_balance_before = usdc.balanceOf(test_usdc_account)
    usdc_in_fund_before = usdc.balanceOf(fund_through_proxy_usdc_after_hardwork)
    strategy_balance_before = aavev2strat.investedUnderlyingBalance()

    fund_through_proxy_usdc_after_hardwork.withdraw(shares_to_withdraw, {'from': test_usdc_account})

    fund_balance_after = fund_through_proxy_usdc_after_hardwork.balanceOf(test_usdc_account)
    usdc_balance_after = usdc.balanceOf(test_usdc_account)
    usdc_in_fund_after = usdc.balanceOf(fund_through_proxy_usdc_after_hardwork)
    strategy_balance_after = aavev2strat.investedUnderlyingBalance()
    print(fund_balance_before, fund_balance_after, strategy_balance_before, strategy_balance_after, usdc_balance_before, usdc_balance_after, usdc_in_fund_before, usdc_in_fund_after)

    assert fund_balance_before - fund_balance_after == shares_to_withdraw
    assert float(usdc_balance_after - usdc_balance_before) == pytest.approx(amount_to_withdraw)
    assert usdc_in_fund_after == 0
    assert float(strategy_balance_before - strategy_balance_after) == pytest.approx(amount_to_withdraw - usdc_in_fund_before)

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_remove_strategy(fund_through_proxy_usdc_after_hardwork, aavev2strat, usdc, accounts):

    total_value_locked_before = fund_through_proxy_usdc_after_hardwork.totalValueLocked()
    fund_balance_before = usdc.balanceOf(fund_through_proxy_usdc_after_hardwork)
    strategy_balance_before = aavev2strat.investedUnderlyingBalance()

    tx = fund_through_proxy_usdc_after_hardwork.removeStrategy(aavev2strat, {'from':accounts[1]})

    total_value_locked_after = fund_through_proxy_usdc_after_hardwork.totalValueLocked()
    strategy_balance_after = aavev2strat.investedUnderlyingBalance()
    fund_balance_after = usdc.balanceOf(fund_through_proxy_usdc_after_hardwork)
    print(total_value_locked_before, total_value_locked_after, strategy_balance_before, strategy_balance_after)

    assert fund_through_proxy_usdc_after_hardwork.getStrategyList() == []
    assert tx.events["StrategyRemoved"].values() == [aavev2strat]
    assert float(total_value_locked_before) == pytest.approx(total_value_locked_after)
    assert strategy_balance_after == 0
    assert float(fund_balance_after-fund_balance_before) == pytest.approx(strategy_balance_before)

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_hardwork_with_invest_activate_false(fund_through_proxy_usdc_with_strategy_and_deposit, aavev2strat, usdc, accounts, interface):
    deposited_amout = 1000 * (10 ** usdc.decimals())
    aToken = aavev2strat.aToken()
    atoken_balance_before = interface.IERC20(aToken).balanceOf(aavev2strat)
    aavev2strat.setInvestActivated(False, {'from': accounts[0]})
    underlying_balance_before = usdc.balanceOf(aavev2strat)
    fund_through_proxy_usdc_with_strategy_and_deposit.doHardWork({'from': accounts[1]})
    underlying_balance_after = usdc.balanceOf(aavev2strat)
    atoken_balance_after = interface.IERC20(aToken).balanceOf(aavev2strat)
    assert underlying_balance_after == deposited_amout*strategy_weightage/10000
    assert atoken_balance_after == atoken_balance_before

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_set_invest_activate_with_random_address(fund_through_proxy_usdc_with_strategy_and_deposit, aavev2strat, usdc, accounts, interface):
    with brownie.reverts("The sender has to be the governance or fund manager"):
        aavev2strat.setInvestActivated(False, {'from': accounts[7]})

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_partial_withdraw_shares_with_random_address(fund_through_proxy_usdc_after_hardwork, aavev2strat, accounts, interface):
    aToken = aavev2strat.aToken()
    atoken_balance = interface.IERC20(aToken).balanceOf(aavev2strat)
    atokens_to_withdraw = atoken_balance/4
    with brownie.reverts("The sender has to be the governance or fund manager"):
        aavev2strat.withdrawPartialShares(atokens_to_withdraw, {'from': accounts[7]})

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_partial_withdraw_shares(fund_through_proxy_usdc_after_hardwork, aavev2strat, usdc, accounts, interface):
    aToken = aavev2strat.aToken()
    underlying_balance_before = usdc.balanceOf(aavev2strat)
    underlying_to_withdraw = 200 * (10 ** usdc.decimals())
    atokens_to_withdraw = underlying_to_withdraw * (10 ** interface.ERC20(aToken).decimals())/(10 ** usdc.decimals())
    aavev2strat.withdrawPartialShares(atokens_to_withdraw, {'from': accounts[1]})
    underlying_balance_after = usdc.balanceOf(aavev2strat)
    assert underlying_balance_after == underlying_to_withdraw + underlying_balance_before

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_withdraw_to_fund_with_random_address(fund_through_proxy_usdc_after_hardwork, aavev2strat, usdc, accounts, interface):
    aToken = aavev2strat.aToken()
    underlying_to_withdraw = 200 * (10 ** usdc.decimals())
    atokens_to_withdraw = underlying_to_withdraw * (10 ** interface.ERC20(aToken).decimals())/(10 ** usdc.decimals())
    with brownie.reverts("The sender has to be the fund"):
        aavev2strat.withdrawToFund(atokens_to_withdraw, {'from': accounts[7]})


@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_withdrawall_to_fund_with_random_address(fund_through_proxy_usdc_after_hardwork, aavev2strat, usdc, accounts, interface): 
    with brownie.reverts("The sender has to be the fund"):
        aavev2strat.withdrawAllToFund({'from': accounts[7]})


@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_sweep_with_random_address(fund_through_proxy_usdc_after_hardwork, aavev2strat, accounts, interface): 
    uni_token_address = "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984"
    random_uni_holder = "0x47173b170c64d16393a52e6c480b3ad8c302ba1e"
    interface.ERC20(uni_token_address).transfer(
        aavev2strat,
        200 * (10 ** 18),
        {'from':random_uni_holder}
    )
    with brownie.reverts("Not governance"):
        aavev2strat.sweep(uni_token_address, random_uni_holder, {'from': accounts[7]})

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_sweep_with_reward_tokens(fund_through_proxy_usdc_after_hardwork, aavev2strat, accounts, interface): 
    reward_token_address = "0x4da27a545c0c5B758a6BA100e3a049001de870f5"
    random_reward_token_holder = "0xc4a936b003bc223df757b35ee52f6da66b062935"
    interface.ERC20(reward_token_address).transfer(
        aavev2strat,
        200 * (10 ** 18),
        {'from':random_reward_token_holder}
    )
    with brownie.reverts("Token is restricted"):
        aavev2strat.sweep(reward_token_address, random_reward_token_holder, {'from': accounts[0]})

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_sweep_with_uni_tokens(fund_through_proxy_usdc_after_hardwork, aavev2strat, accounts, interface): 
    uni_token_address = "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984"
    random_uni_holder = "0x47173b170c64d16393a52e6c480b3ad8c302ba1e"
    interface.ERC20(uni_token_address).transfer(
        aavev2strat,
        200 * (10 ** 18),
        {'from':random_uni_holder}
    )
    strategy_uni_balance_before = interface.ERC20(uni_token_address).balanceOf(aavev2strat)
    aavev2strat.sweep(uni_token_address, random_uni_holder, {'from': accounts[0]})
    strategy_uni_balance_after = interface.ERC20(uni_token_address).balanceOf(aavev2strat)
    assert strategy_uni_balance_before != 0
    assert strategy_uni_balance_after == 0

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_liquidate_reinvest_with_random_address(aavev2strat, accounts, interface, chain):
    chain.mine(1000)
    reward_token_address = "0x4da27a545c0c5B758a6BA100e3a049001de870f5"
    reward_token_balance = interface.ERC20(reward_token_address).balanceOf(aavev2strat)
    with brownie.reverts("The sender has to be the relayer or fund manager"):
        aavev2strat.liquidateRewardsAndReinvest(reward_token_balance, {'from':accounts[7]})

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_claim_reward_token(fund_through_proxy_usdc_after_hardwork, aavev2strat, accounts, interface, chain):
    reward_token_address = "0x4da27a545c0c5B758a6BA100e3a049001de870f5"
    reward_token_balance_before = interface.ERC20(reward_token_address).balanceOf(aavev2strat)
    chain.mine(1000)
    aavev2strat.claimRewards()
    reward_token_balance_after = interface.ERC20(reward_token_address).balanceOf(aavev2strat)
    assert reward_token_balance_before == 0
    assert reward_token_balance_after != 0
