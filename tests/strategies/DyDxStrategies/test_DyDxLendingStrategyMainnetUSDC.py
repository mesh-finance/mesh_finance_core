import pytest, brownie

strategy_weightage = 8000

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_deployment(DyDxLendingStrategyMainnetUSDC,fund_through_proxy_usdc, usdc, accounts):
    dydxStrat = DyDxLendingStrategyMainnetUSDC.deploy(fund_through_proxy_usdc, {'from': accounts[0]})
    assert dydxStrat.name() == "DyDxLendingStrategyMainnetUSDC"
    assert dydxStrat.version() == "V1"
    assert dydxStrat.canNotSweep(usdc) == True
    assert dydxStrat.marketId() == 2

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_deployment_with_zero_address(DyDxLendingStrategyMainnetUSDC, zero_account, accounts):
    with brownie.reverts("Fund cannot be empty"):
        DyDxLendingStrategyMainnetUSDC.deploy(zero_account, {'from': accounts[0]})

@pytest.fixture
def dydxstrat(DyDxLendingStrategyMainnetUSDC, fund_through_proxy_usdc, accounts):
    return DyDxLendingStrategyMainnetUSDC.deploy(fund_through_proxy_usdc, {'from': accounts[0]})

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_add_strategy(dydxstrat, fund_through_proxy_usdc, accounts):
    tx = fund_through_proxy_usdc.addStrategy(dydxstrat, strategy_weightage, 0, {'from': accounts[1]})
    assert fund_through_proxy_usdc.getStrategyList() == [dydxstrat]
    assert fund_through_proxy_usdc.getStrategy(dydxstrat)[0] == strategy_weightage
    assert fund_through_proxy_usdc.getStrategy(dydxstrat)[1] == 0
    assert tx.events["StrategyAdded"].values() == [dydxstrat, strategy_weightage, 0]

@pytest.fixture
def fund_through_proxy_usdc_with_strategy_and_deposit(fund_through_proxy_usdc, dydxstrat, usdc, test_usdc_account, accounts):
    tx = fund_through_proxy_usdc.addStrategy(dydxstrat, strategy_weightage, 0, {'from': accounts[1]})
    amount_to_deposit = 1000 * (10 ** usdc.decimals())
    usdc.approve(fund_through_proxy_usdc, amount_to_deposit, {'from': test_usdc_account})
    tx = fund_through_proxy_usdc.deposit(amount_to_deposit, {'from': test_usdc_account})
    return fund_through_proxy_usdc

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_hard_work(fund_through_proxy_usdc_with_strategy_and_deposit, dydxstrat, usdc, accounts):

    assert dydxstrat.investedUnderlyingBalance() == 0

    amount_deposited = 1000 * (10 ** usdc.decimals())
    tx = fund_through_proxy_usdc_with_strategy_and_deposit.doHardWork({'from':accounts[1]})

    expected_underlying_strategy = amount_deposited*strategy_weightage/10000

    expected_underlying_balance = dydxstrat.investedUnderlyingBalance()
    assert float(dydxstrat.investedUnderlyingBalance()) == pytest.approx(expected_underlying_strategy)

@pytest.fixture
def fund_through_proxy_usdc_after_hardwork(fund_through_proxy_usdc_with_strategy_and_deposit, accounts):
    
    tx = fund_through_proxy_usdc_with_strategy_and_deposit.doHardWork({'from': accounts[1]})
    
    return fund_through_proxy_usdc_with_strategy_and_deposit

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_withdraw_small(fund_through_proxy_usdc_after_hardwork, dydxstrat, usdc, test_usdc_account):
    
    shares_to_withdraw = 100 * (10 ** fund_through_proxy_usdc_after_hardwork.decimals())
    usdc_to_withdraw = fund_through_proxy_usdc_after_hardwork.underlyingFromShares(shares_to_withdraw)

    user_balance_in_fund_shares_before = fund_through_proxy_usdc_after_hardwork.balanceOf(test_usdc_account)
    user_balance_in_usdc_before = usdc.balanceOf(test_usdc_account)
    fund_balance_in_usdc_before = usdc.balanceOf(fund_through_proxy_usdc_after_hardwork)
    strategy_balance_in_usdc_before = dydxstrat.investedUnderlyingBalance()

    fund_through_proxy_usdc_after_hardwork.withdraw(shares_to_withdraw, {'from': test_usdc_account})

    user_balance_in_fund_shares_after = fund_through_proxy_usdc_after_hardwork.balanceOf(test_usdc_account)
    user_balance_in_usdc_after = usdc.balanceOf(test_usdc_account)
    fund_balance_in_usdc_after = usdc.balanceOf(fund_through_proxy_usdc_after_hardwork)
    strategy_balance_in_usdc_after = dydxstrat.investedUnderlyingBalance()

    assert user_balance_in_fund_shares_before - user_balance_in_fund_shares_after == shares_to_withdraw
    assert float(user_balance_in_usdc_after - user_balance_in_usdc_before) == pytest.approx(usdc_to_withdraw)
    assert float(fund_balance_in_usdc_before - fund_balance_in_usdc_after) == pytest.approx(usdc_to_withdraw)
    assert float(strategy_balance_in_usdc_before) == pytest.approx(strategy_balance_in_usdc_after)

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_withdraw_large(fund_through_proxy_usdc_after_hardwork, dydxstrat, usdc, test_usdc_account):
    
    shares_to_withdraw = 500 * (10 ** fund_through_proxy_usdc_after_hardwork.decimals())
    usdc_to_withdraw = fund_through_proxy_usdc_after_hardwork.underlyingFromShares(shares_to_withdraw)

    user_balance_in_fund_shares_before = fund_through_proxy_usdc_after_hardwork.balanceOf(test_usdc_account)
    user_balance_in_usdc_before = usdc.balanceOf(test_usdc_account)
    fund_balance_in_usdc_before = usdc.balanceOf(fund_through_proxy_usdc_after_hardwork)
    strategy_balance_in_usdc_before = dydxstrat.investedUnderlyingBalance()

    fund_through_proxy_usdc_after_hardwork.withdraw(shares_to_withdraw, {'from': test_usdc_account})

    user_balance_in_fund_shares_after = fund_through_proxy_usdc_after_hardwork.balanceOf(test_usdc_account)
    user_balance_in_usdc_after = usdc.balanceOf(test_usdc_account)
    fund_balance_in_usdc_after = usdc.balanceOf(fund_through_proxy_usdc_after_hardwork)
    strategy_balance_in_usdc_after = dydxstrat.investedUnderlyingBalance()

    assert user_balance_in_fund_shares_before - user_balance_in_fund_shares_after == shares_to_withdraw
    assert float(user_balance_in_usdc_after - user_balance_in_usdc_before) == pytest.approx(usdc_to_withdraw)
    assert fund_balance_in_usdc_after == 0
    assert float(strategy_balance_in_usdc_before - strategy_balance_in_usdc_after) == pytest.approx(usdc_to_withdraw - fund_balance_in_usdc_before)

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_remove_strategy(fund_through_proxy_usdc_after_hardwork, dydxstrat, usdc, accounts):

    total_value_locked_before = fund_through_proxy_usdc_after_hardwork.totalValueLocked()
    fund_balance_before = usdc.balanceOf(fund_through_proxy_usdc_after_hardwork)
    strategy_balance_before = dydxstrat.investedUnderlyingBalance()

    tx = fund_through_proxy_usdc_after_hardwork.removeStrategy(dydxstrat, {'from': accounts[1]})

    total_value_locked_after = fund_through_proxy_usdc_after_hardwork.totalValueLocked()
    strategy_balance_after = dydxstrat.investedUnderlyingBalance()
    fund_balance_after = usdc.balanceOf(fund_through_proxy_usdc_after_hardwork)

    assert fund_through_proxy_usdc_after_hardwork.getStrategyList() == []
    assert tx.events["StrategyRemoved"].values() == [dydxstrat]
    assert float(total_value_locked_before) == pytest.approx(total_value_locked_after)
    assert strategy_balance_after == 0
    assert float(fund_balance_after-fund_balance_before) == pytest.approx(strategy_balance_before)

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_hardwork_with_invest_activate_false(fund_through_proxy_usdc_with_strategy_and_deposit, dydxstrat, usdc, accounts):
    usdc_balance_in_dydx_before = dydxstrat.underlyingValueInDyDx()
    dydxstrat.setInvestActivated(False, {'from': accounts[0]})
    underlying_balance_before = usdc.balanceOf(dydxstrat)
    fund_through_proxy_usdc_with_strategy_and_deposit.doHardWork({'from': accounts[1]})
    underlying_balance_after = usdc.balanceOf(dydxstrat)
    usdc_balance_in_dydx_after = dydxstrat.underlyingValueInDyDx()
    assert underlying_balance_before >= underlying_balance_before
    assert usdc_balance_in_dydx_before == usdc_balance_in_dydx_after

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_set_invest_activate_with_random_address(fund_through_proxy_usdc_with_strategy_and_deposit, dydxstrat, accounts):
    with brownie.reverts("The sender has to be the governance or fund manager"):
        dydxstrat.setInvestActivated(False, {'from': accounts[7]})

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_partial_withdraw_fund_with_random_address(fund_through_proxy_usdc_after_hardwork, dydxstrat, accounts):
    with brownie.reverts("The sender has to be the governance or fund manager"):
        dydxstrat.withdrawPartialFund(100, {'from': accounts[7]})

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_partial_withdraw_fund(fund_through_proxy_usdc_after_hardwork, dydxstrat, usdc):
    usdc_balance_in_dydx_before = dydxstrat.underlyingValueInDyDx()
    underlying_to_withdraw = 200 * (10 ** usdc.decimals())
    dydxstrat.withdrawPartialFund(underlying_to_withdraw)
    usdc_balance_in_dydx_after = dydxstrat.underlyingValueInDyDx()
    assert float(usdc_balance_in_dydx_after + underlying_to_withdraw) == pytest.approx(usdc_balance_in_dydx_before)

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_withdraw_to_fund_with_random_address(fund_through_proxy_usdc_after_hardwork, dydxstrat, usdc, accounts):
    underlying_to_withdraw = 200 * (10 ** usdc.decimals())
    with brownie.reverts("The sender has to be the fund"):
        dydxstrat.withdrawToFund(underlying_to_withdraw, {'from': accounts[7]})

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_withdrawall_to_fund_with_random_address(fund_through_proxy_usdc_after_hardwork, dydxstrat, accounts): 
    with brownie.reverts("The sender has to be the fund"):
        dydxstrat.withdrawAllToFund({'from': accounts[7]})


@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_sweep_with_random_address(fund_through_proxy_usdc_after_hardwork, dydxstrat, accounts, interface): 
    uni_token_address = "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984"
    random_uni_holder = "0x47173b170c64d16393a52e6c480b3ad8c302ba1e"
    interface.ERC20(uni_token_address).transfer(
        dydxstrat,
        200 * (10 ** 18),
        {'from':random_uni_holder}
    )
    with brownie.reverts("Not governance"):
        dydxstrat.sweep(uni_token_address, random_uni_holder, {'from': accounts[7]})

#  There is no reward token for dydx
# @pytest.mark.require_network("mainnet-fork", "hardhat-fork")
# def test_sweep_with_reward_tokens(fund_through_proxy_usdc_after_hardwork, dydxstrat, accounts, interface): 
#     reward_token_address = "0x4da27a545c0c5B758a6BA100e3a049001de870f5"
#     random_reward_token_holder = "0xc4a936b003bc223df757b35ee52f6da66b062935"
#     interface.ERC20(reward_token_address).transfer(
#         dydxstrat,
#         200 * (10 ** 18),
#         {'from':random_reward_token_holder}
#     )
#     with brownie.reverts("Token is restricted"):
#         dydxstrat.sweep(reward_token_address, random_reward_token_holder, {'from': accounts[0]})

@pytest.mark.require_network("mainnet-fork", "hardhat-fork")
def test_sweep_with_uni_tokens(fund_through_proxy_usdc_after_hardwork, dydxstrat, accounts, interface): 
    uni_token_address = "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984"
    random_uni_holder = "0x47173b170c64d16393a52e6c480b3ad8c302ba1e"
    interface.ERC20(uni_token_address).transfer(
        dydxstrat,
        200 * (10 ** 18),
        {'from':random_uni_holder}
    )
    strategy_uni_balance_before = interface.ERC20(uni_token_address).balanceOf(dydxstrat)
    dydxstrat.sweep(uni_token_address, random_uni_holder, {'from': accounts[0]})
    strategy_uni_balance_after = interface.ERC20(uni_token_address).balanceOf(dydxstrat)
    assert strategy_uni_balance_before != 0
    assert strategy_uni_balance_after == 0

# Nothing to liquidate
# @pytest.mark.require_network("mainnet-fork", "hardhat-fork")
# def test_liquidate_reinvest_with_random_address(dydxstrat, accounts, interface, chain):
#     chain.mine(1000)
#     reward_token_address = "0x4da27a545c0c5B758a6BA100e3a049001de870f5"
#     reward_token_balance = interface.ERC20(reward_token_address).balanceOf(dydxstrat)
#     with brownie.reverts("The sender has to be the governance or fund"):
#         dydxstrat.liquidateRewardsAndReinvest(reward_token_balance, {'from':accounts[7]})
