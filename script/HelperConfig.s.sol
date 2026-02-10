// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

abstract contract CodeConstants {
    /* Global Allocation Deploy values */
    uint24 constant DESIRED_ETH_ALLOCATION_PERCENTAGE = 500000; // 50%
    uint24 constant REBALANCE_THRESHOLD = 40000; // 4%
    uint24 constant SLIPPAGE_MAINNET = 6500; // .65%
    uint24 constant SLIPPAGE_SEPOLIA = 50000; // 5%
    uint256 constant ETH_PRICE_MIN = 1000000000; // $1000 w/ 6 decimals
    uint256 constant ETH_PRICE_MAX = 8000000000; // $8000 w/ 6 decimals
    uint256 constant FACTOR = 15e17; // 1.5

    /* WETH Addresses */
    address constant WETH_MAINNET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH token address on Ethereum Mainnet
    address constant WETH_SEPOLIA = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14; // WETH token address on Ethereum Sepolia *Defined on Uni contract
    /* USD Addresses https://developers.circle.com/stablecoins/usdc-contract-addresses */
    address constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC token address on Ethereum Mainnet
    address constant USDC_SEPOLIA = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; // USDC token address on Ethereum Sepolia

    /* Uniswap Addresses https://docs.uniswap.org/contracts/v2/reference/smart-contracts/v2-deployments*/
    address constant UNISWAP_V2_ROUTER02_MAINNET = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Uniswap V2 Router address on Ethereum Mainnet
    address constant UNISWAP_V2_ROUTER02_SEPOLIA = 0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3; // Uniswap V2 Router address on Ethereum Sepolia

    /* Chain IDs */
    uint256 public constant ETH_MAINNET_CHAIN_ID = 1;
    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    // uint256 public constant LOCAL_CHAIN_ID = 31337;
}

contract HelperConfig is CodeConstants, Script {
    error HelperConfig__InvalidChainId();

    struct NetworkConfig {
        address token1;
        address token2;
        address uniswapRouter;
        uint24 desiredAllocationPercentage;
        uint24 rebalanceThreshold;
        uint24 slippagePercentage;
        address senderAddress;
        uint256 ethPriceMin;
        uint256 ethPriceMax;
        uint256 factor;
    }

    mapping(uint256 => NetworkConfig) public networkConfigs;

    constructor() {
        networkConfigs[ETH_MAINNET_CHAIN_ID] = getMainnetEthConfig();
        networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
        // networkConfigs[LOCAL_CHAIN_ID] = getLocalConfig();
    }

    function setConfig(uint256 chainId, NetworkConfig memory networkConfig) public {
        networkConfigs[chainId] = networkConfig;
    }

    function getConfig() public view returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getConfigByChainId(uint256 chainId) public view returns (NetworkConfig memory) {
        if (networkConfigs[chainId].token1 != address(0)) {
            return networkConfigs[chainId];
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getMainnetEthConfig() public view returns (NetworkConfig memory) {
        address senderAddress = vm.parseAddress(vm.envString("MAINNET_WALLET_ADDRESS"));
        return NetworkConfig({
            token1: WETH_MAINNET,
            token2: USDC_MAINNET,
            uniswapRouter: UNISWAP_V2_ROUTER02_MAINNET,
            desiredAllocationPercentage: DESIRED_ETH_ALLOCATION_PERCENTAGE,
            rebalanceThreshold: REBALANCE_THRESHOLD,
            slippagePercentage: SLIPPAGE_MAINNET,
            senderAddress: senderAddress,
            ethPriceMin: ETH_PRICE_MIN,
            ethPriceMax: ETH_PRICE_MAX,
            factor: FACTOR
        });
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        address senderAddress = vm.parseAddress(vm.envString("SEPOLIA_WALLET_ADDRESS"));
        return NetworkConfig({
            token1: WETH_SEPOLIA,
            token2: USDC_SEPOLIA,
            uniswapRouter: UNISWAP_V2_ROUTER02_SEPOLIA,
            desiredAllocationPercentage: DESIRED_ETH_ALLOCATION_PERCENTAGE,
            rebalanceThreshold: REBALANCE_THRESHOLD,
            slippagePercentage: SLIPPAGE_SEPOLIA,
            senderAddress: senderAddress,
            ethPriceMin: ETH_PRICE_MIN,
            ethPriceMax: ETH_PRICE_MAX,
            factor: FACTOR
        });
    }
}
