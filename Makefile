-include .env

.PHONY: all test deploy

build :; forge build

test-sepolia :; forge test --fork-url $(SEPOLIA_RPC_URL)

test-mainnet :; forge test --fork-url $(MAINNET_RPC_URL)

test-all :; forge test --fork-url $(MAINNET_RPC_URL) && forge test --fork-url $(SEPOLIA_RPC_URL)

deploy-sepolia :
	@forge script script/DeployGlobalAllocation.s.sol:DeployGlobalAllocation --rpc-url $(SEPOLIA_RPC_URL) --account $(CAST_WALLET) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv

deploy-mainnet :
	@forge script script/DeployGlobalAllocation.s.sol:DeployGlobalAllocation --rpc-url $(MAINNET_RPC_URL) --account $(CAST_WALLET) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv