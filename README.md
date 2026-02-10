## Foundry

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/


## Setup Environment

Use env.example to create your own .env file

```shell
$ source .env
```

## Usage

### Install Dependencies

```shell
$ make install
```

### Build

```shell
$ forge build
```

### Test

```shell
$ make test-all
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Deploy on testnet

```shell
$ make deploy-sepolia
```

### Deploy on testnet

```shell
$ make deploy-mainnet
```

## Cast

### View Wallets

```shell
$ cast wallet list
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
