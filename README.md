# Introduction

This is the official repo of [Mesh Finance](https://mesh.finance).

## Installation and Setup

1. [Install Brownie](https://eth-brownie.readthedocs.io/en/stable/install.html) & [Ganache-CLI](https://github.com/trufflesuite/ganache-cli).

2. Sign up for [Infura](https://infura.io/) and generate an API key. Store it in the `WEB3_INFURA_PROJECT_ID` environment variable.

```bash
export WEB3_INFURA_PROJECT_ID=ProjectID
```

3. Sign up for [Etherscan](www.etherscan.io) and generate an API key. This is required for fetching source codes of the mainnet contracts like DAI, yvaults etc. Store the API key in the `ETHERSCAN_TOKEN` environment variable.

```bash
export ETHERSCAN_TOKEN=ApiToken
```
4. Compile the project. This will also install the dependencies from the config file.

```bash
brownie compile
```

## Testing

Current scope of testing is funds contracts. For specific strategies, testing needs to be done manually for now.

To run the tests:

```
brownie test
```

This will run all the tests in the test folder. By default, this is configured to run on the mainnet-fork.

You can run the tests on local ganache blockchain using development flag.

```
brownie test --network development
```

Check [Brownie documentation for testing](https://eth-brownie.readthedocs.io/en/stable/tests-pytest-intro.html) and [Brownie documentation for networks](https://eth-brownie.readthedocs.io/en/stable/network-management.html).