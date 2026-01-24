// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract GlobalAllocation is Ownable {
    uint24 public desiredEthToTokenAllocationPercentage; // percentage allocation for ( ETH(in USD) / ETH(in USD) * USDC ) * 1000000, number 1.0000%-100.0000%
    uint24 public currentEthToUsdcAllocationPercentage; // percentage allocation for ( ETH(in USD) / ETH(in USD) * USDC ) * 1000000, number 0%-100.0000%
    uint24 public rebalancePercentage; // percentage of the portfolio to rebalance at a time

    /* Type Declarations */
    enum AllocationState {
        BALANCED,
        AFTER_DEPOSIT,
        AFTER_ETH_QUOTE,
        CURRENT_ALLOCATION_PERCENTAGE_UPDATED
    }

    /* State Variables */
    address private immutable I_TOKEN1; // Specify token1 address (ETH)
    address private immutable i_token2; // Specify token2 address (USDT)

    uint256 private s_totalPortfolioValueInToken2;
    uint256 private s_ethValueInToken2;
    address[] private s_Token1ToToken2Path;
    address[] private s_Token2ToToken1Path;
    AllocationState private s_allocationState;

    IUniswapV2Router02 private immutable i_UNISWAP_V2_ROUTER_02;

    constructor(
        address _token1,
        address _token2,
        address _uniswapRouter,
        uint24 _desiredEthToTokenAllocationPercentage,
        uint24 _rebalancePercentage
    ) Ownable(msg.sender) {
        require(
            _desiredEthToTokenAllocationPercentage <= 1000000 && _desiredEthToTokenAllocationPercentage >= 10000,
            "Allocation percentage must be between 1.0000% and 100.0000%"
        );
        require(
            _rebalancePercentage <= 100000 && _rebalancePercentage >= 1000,
            "Rebalance percentage must be between 0.1000% and 10.0000%"
        );

        I_TOKEN1 = _token1;
        i_token2 = _token2;
        s_Token1ToToken2Path = [I_TOKEN1, i_token2];
        s_Token2ToToken1Path = [i_token2, I_TOKEN1];
        i_UNISWAP_V2_ROUTER_02 = IUniswapV2Router02(_uniswapRouter);
        desiredEthToTokenAllocationPercentage = _desiredEthToTokenAllocationPercentage;
        rebalancePercentage = _rebalancePercentage;
    }

    /**
     * @dev Updates the current allocation percentage based on Uniswap quoted Eth price
     * If immediatley after deposit use ChainLink Priceffeed to get ETH value in token2 terms
     * Otherwise use a Uniswap quote to get ETH value in token2 terms
     */
    function quoteEthPriceInToken2() public {
        // Placeholder function to update current allocation percentage
        // Either make an overload or a variable to specify a balancing after
        // depositing funds that uses chainlink oracle for a more accurate quote price
        if (s_allocationState == AllocationState.AFTER_DEPOSIT) {
            // Use Chainlink price feed to get ETH price in USD

            s_ethValueInToken2 = 100;
            s_allocationState = AllocationState.BALANCED;
        } else {
            uint256[] memory returnAmounts =
                i_UNISWAP_V2_ROUTER_02.getAmountsOut(address(this).balance, s_Token1ToToken2Path);
            s_ethValueInToken2 - returnAmounts[1]; // returnAmount[1] is a quote for all eth in the contract in terms of token2
        }

        // Update state
        s_allocationState = AllocationState.AFTER_ETH_QUOTE;
    }

    /**
     * @dev Update Portfolio based on most recently quoted token2 value
     */
    function updateCurrentAllocationPercentage() public {
        s_totalPortfolioValueInToken2 = s_ethValueInToken2 + IERC20(i_token2).balanceOf(address(this));

        if (s_totalPortfolioValueInToken2 == 0) {
            currentEthToUsdcAllocationPercentage = 0;
            return;
        } else {
            require(
                (s_ethValueInToken2 * 1000000) / s_totalPortfolioValueInToken2 < type(uint24).max,
                "Value will be truncated when type casting"
            );
            // casting to 'uint24' is safe because require statement above ensures value ≤ type(uint24).max
            // forge-lint: disable-next-line(unsafe-typecast)
            currentEthToUsdcAllocationPercentage =
                uint24((s_ethValueInToken2 * 1000000) / s_totalPortfolioValueInToken2);
        }

        // Update State
        s_allocationState = AllocationState.CURRENT_ALLOCATION_PERCENTAGE_UPDATED;
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
        // Get the most recent Eth quote
        quoteEthPriceInToken2();

        // Update the current allocation percentage
        updateCurrentAllocationPercentage();

        // Logic for balancing funds
        if (currentEthToUsdcAllocationPercentage < desiredEthToTokenAllocationPercentage) {
            swapTokenForEth();
        } else if (currentEthToUsdcAllocationPercentage > desiredEthToTokenAllocationPercentage) {
            swapEthForToken();
        } else {
            return;
        }
    }

    /**
     * @dev Swaps ETH for token address using Uniswap
     */
    function swapEthForToken() internal {
        uint256 minTokenToRecieve = (currentEthToUsdcAllocationPercentage - desiredEthToTokenAllocationPercentage)
            * s_totalPortfolioValueInToken2 / 1000000;

        // Use quoted price to send the max eth required for transaction to go through
        uint256 maxEthToSend = minTokenToRecieve / s_ethValueInToken2;

        i_UNISWAP_V2_ROUTER_02.swapExactETHForTokens{value: maxEthToSend}({
            amountOutMin: minTokenToRecieve,
            path: s_Token1ToToken2Path,
            to: address(this),
            deadline: block.timestamp + 15 minutes
        });
    }

    /**
     * @dev Swaps token for ETH using Uniswap
     */
    function swapTokenForEth() internal {
        uint256 maxTokenToSend = (desiredEthToTokenAllocationPercentage - currentEthToUsdcAllocationPercentage)
            * s_totalPortfolioValueInToken2 / 100000;
        uint256 minEthToRecieve = maxTokenToSend / s_ethValueInToken2;

        // Approve Uniswap router to spend USDC
        IERC20(i_token2).approve(address(i_UNISWAP_V2_ROUTER_02), maxTokenToSend);

        i_UNISWAP_V2_ROUTER_02.swapExactTokensForETH({
            amountIn: maxTokenToSend,
            amountOutMin: minEthToRecieve,
            path: s_Token2ToToken1Path,
            to: address(this),
            deadline: block.timestamp + 15 minutes
        });
    }

    /**
     * @dev Accept ETH deposits
     * Intentianally do not allow deposits of other tokens, only ETH
     */
    receive() external payable {
        require(msg.value > 0, "Must send ETH to deposit");

        // Setting post deposit state so the next re-balance uses Chainlink price feed instead of Uniswap quote
        s_allocationState = AllocationState.AFTER_DEPOSIT;
    }

    function withdraw() external onlyOwner {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        require(success, "Transfer failed");
        // Add a way to withdraw the token
    }
}
