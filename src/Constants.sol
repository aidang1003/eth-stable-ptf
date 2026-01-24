// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Uniswap Addresses
address constant UNISWAP_V2_ROUTER02 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Uniswap V2 Router address on Ethereum mainnet
address constant UNISWAP_V2_PAIR_ETH_USDC = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc; // ethereum mainnet ETH/USDC V2 pair address, accepts WETH and will automtically convert ETH to WETH

// Chainlink Addresses https://docs.chain.link/data-feeds/price-feeds/addresses
address constant MAINNET_ETH_USDC_ORACLE_ADDRESS = 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4; // Ethereum mainnet ETH/USDC price oracle address
address constant MAINNET_ETH_USDT_ORACLE_ADDRESS = 0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46; // Ethereum mainnet ETH/USDT price oracle address

address constant SEPOLIA_ETH_USD_ORACLE_ADDRESS = 0x694AA1769357215DE4FAC081bf1f309aDC325306; // Ethereum Sepolia ETH/USD price oracle address

// Token Addresses
address constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC token address on Ethereum mainnet
address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH token address on Ethereum mainnet
