// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UNISWAP_V2_ROUTER02} from "./Constants.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract GlobalAllocation is Ownable {
    uint24 public immutable desiredEthToUsdcAllocationPerccentage; // percentage allocation for ( ETH(in USD) / ETH(in USD) * USDC ) * 1000000, number 1.0000%-100.0000%
    uint24 public currentEthToUsdcAllocationPercentage; // percentage allocation for ( ETH(in USD) / ETH(in USD) * USDC ) * 1000000, number 0%-100.0000%
    uint24 public immutable rebalancePercentage; // percentage of the portfolio to rebalance at a time

    /* Immutable Global Variables */
    address public immutable i_token1; // Specify token1 address (ETH)
    address public immutable i_token2; // Specify token2 address (USDT)
    address[] private s_Token1ToToken2Path;
    address[] private s_Token2ToToken1Path;
    uint256[] private returnAmounts = new uint256[](2);

    IUniswapV2Router02 private immutable uniswapV2Router02;

    constructor(
        address _token1,
        address _token2,
        address _uniswapRouter,
        uint24 _desiredEthToUsdcAllocationPerccentage,
        uint24 _rebalancePercentage
    ) Ownable(msg.sender) {
        require(
            _desiredEthToUsdcAllocationPerccentage <= 1000000 && _desiredEthToUsdcAllocationPerccentage >= 10000,
            "Allocation percentage must be between 1.0000% and 100.0000%"
        );
        require(
            _rebalancePercentage <= 100000 && _rebalancePercentage >= 1000,
            "Rebalance percentage must be between 0.1000% and 10.0000%"
        );

        i_token1 = _token1;
        i_token2 = _token2;
        s_Token1ToToken2Path = [i_token1, i_token2];
        s_Token2ToToken1Path = [i_token2, i_token1];
        uniswapV2Router02 = IUniswapV2Router02(_uniswapRouter);
        desiredEthToUsdcAllocationPerccentage = _desiredEthToUsdcAllocationPerccentage;
        rebalancePercentage = _rebalancePercentage;
    }

    /**
     * @dev Updates the current allocation percentage based on Uniswap quoted Eth price
     */
    function updateCurrentAllocationPercentage() public {
        // Placeholder function to update current allocation percentage
        // Either make an overload or a variable to specify a balancing after
        // depositing funds that uses chainlink oracle for a more accurate quote price
    }

    /**
     * @dev Allow owner to balance funds manually
     */
    function balanceFundsExternal() external onlyOwner {
        balanceFunds();
    }

    /**
     * @dev Balances funds based on desired allocation percentage
     * Only needs to be called once at the contract creation
     */
    function balanceFunds() internal {
        // Update the current allocation percentage
        updateCurrentAllocationPercentage();

        // Logic for balancing funds
        if (currentEthToUsdcAllocationPercentage < desiredEthToUsdcAllocationPerccentage) {
            swapTokenForEth();
        } else if (currentEthToUsdcAllocationPercentage > desiredEthToUsdcAllocationPerccentage) {
            swapEthForToken();
        } else {
            return;
        }

        // Create limits after rebalancing so contract doesn't get into an idle state
        createLimits();
    }

    /**
     * @dev Swaps ETH for token address using Uniswap
     */
    function swapEthForToken() internal {
        uint256 maxEthToSend = (address(this).balance * rebalancePercentage) / 1000000;
        uint256 minUsdcToRecieve = (returnAmounts[1] * (1000000 - rebalancePercentage)) / 1000000;

        returnAmounts = uniswapV2Router02.swapExactETHForTokens{value: maxEthToSend}({
            amountOutMin: minUsdcToRecieve, path: s_Token1ToToken2Path, to: address(this), deadline: block.timestamp + 15 minutes
        });
    }

    /**
     * @dev Swaps token for ETH using Uniswap
     */
    function swapTokenForEth() internal {
        // Place holder swap code
    }

    /**
     * @dev Creates a limit order at the current price +- the rebalance percentage
     */
    function createLimits() internal {
        // Create limit for +rebalance percentage
        // Create limit for -rebalance percentage
    }

    /**
     * @dev Cancels existing limit orders
     * Called by contract owner to pause rebalancing
     */
    function cancelLimitsExternal() external onlyOwner returns (bool success) {
        // Place holder cancel limits code
        success = cancelLimits();
    }

    /**
     * @dev Called by withdraw function to cancel limits before withdrawing funds
     */
    function cancelLimits() internal returns (bool success) {
        // Place holder cancel limits code
        success = true;
    }

    /**
     * @dev Accept ETH deposits
     * Intentianally do not allow deposits of other tokens, only ETH
     */
    receive() external payable {
        // Accept ETH deposits
        require(msg.value > 0, "Must send ETH to deposit");
        balanceFunds();
    }

    function withdraw() external onlyOwner {
        require(cancelLimits(), "Failed to cancel existing limits");
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }
}
