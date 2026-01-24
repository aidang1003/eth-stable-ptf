// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

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
    address private immutable I_TOKEN2; // Specify token2 address (USDT)
    AggregatorV3Interface private immutable I_CHAINLINK_PRICE_FEED; // ETH/Token2 price feed

    uint256 private sTotalPortfolioValueInToken2;
    uint256 private sEthValueInToken2;
    address[] private sToken1ToToken2Path;
    address[] private sToken2ToToken1Path;
    AllocationState private sAllocationState;

    IUniswapV2Router02 private immutable I_UNISWAP_V2_ROUTER_02;

    constructor(
        address _token1,
        address _token2,
        address _uniswapRouter,
        address _chainlinkPriceFeed,
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
        I_TOKEN2 = _token2;
        I_CHAINLINK_PRICE_FEED = AggregatorV3Interface(_chainlinkPriceFeed);
        sToken1ToToken2Path = [I_TOKEN1, I_TOKEN2];
        sToken2ToToken1Path = [I_TOKEN2, I_TOKEN1];
        I_UNISWAP_V2_ROUTER_02 = IUniswapV2Router02(_uniswapRouter);
        desiredEthToTokenAllocationPercentage = _desiredEthToTokenAllocationPercentage;
        rebalancePercentage = _rebalancePercentage;
    }

    /**
     * @dev Updates the current allocation percentage based on Uniswap quoted Eth price
     * If immediatley after deposit use ChainLink Priceffeed to get ETH value in token2 terms
     * Otherwise use a Uniswap quote to get ETH value in token2 terms
     */
    function quoteEthPriceInToken2() public {
        if (sAllocationState == AllocationState.AFTER_DEPOSIT) {
            // Use Chainlink price feed to get ETH price in Token2
            (, int256 price,,,) = I_CHAINLINK_PRICE_FEED.latestRoundData();
            require(price > 0, "Invalid price from oracle");

            // Get the number of decimals from the price feed
            uint8 decimals = I_CHAINLINK_PRICE_FEED.decimals();

            // Calculate ETH value in Token2 terms: (ETH balance * price) / (10 ** decimals)
            sEthValueInToken2 = (address(this).balance * uint256(price)) / (10 ** decimals);
        } else {
            uint256[] memory returnAmounts =
                I_UNISWAP_V2_ROUTER_02.getAmountsOut(address(this).balance, sToken1ToToken2Path);
            sEthValueInToken2 - returnAmounts[1]; // returnAmount[1] is a quote for all eth in the contract in terms of token2
        }

        // Update state
        sAllocationState = AllocationState.AFTER_ETH_QUOTE;
    }

    /**
     * @dev Update Portfolio based on most recently quoted token2 value
     */
    function updateCurrentAllocationPercentage() public {
        sTotalPortfolioValueInToken2 = sEthValueInToken2 + IERC20(I_TOKEN2).balanceOf(address(this));

        if (sTotalPortfolioValueInToken2 == 0) {
            currentEthToUsdcAllocationPercentage = 0;
            return;
        } else {
            require(
                (sEthValueInToken2 * 1000000) / sTotalPortfolioValueInToken2 < type(uint24).max,
                "Value will be truncated when type casting"
            );
            // casting to 'uint24' is safe because require statement above ensures value ≤ type(uint24).max
            // forge-lint: disable-next-line(unsafe-typecast)
            currentEthToUsdcAllocationPercentage = uint24((sEthValueInToken2 * 1000000) / sTotalPortfolioValueInToken2);
        }

        // Update State
        sAllocationState = AllocationState.CURRENT_ALLOCATION_PERCENTAGE_UPDATED;
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
            * sTotalPortfolioValueInToken2 / 1000000;

        // Use quoted price to send the max eth required for transaction to go through
        uint256 maxEthToSend = minTokenToRecieve / sEthValueInToken2;

        I_UNISWAP_V2_ROUTER_02.swapExactETHForTokens{value: maxEthToSend}({
            amountOutMin: minTokenToRecieve,
            path: sToken1ToToken2Path,
            to: address(this),
            deadline: block.timestamp + 15 minutes
        });
    }

    /**
     * @dev Swaps token for ETH using Uniswap
     */
    function swapTokenForEth() internal {
        uint256 maxTokenToSend = (desiredEthToTokenAllocationPercentage - currentEthToUsdcAllocationPercentage)
            * sTotalPortfolioValueInToken2 / 100000;
        uint256 minEthToRecieve = maxTokenToSend / sEthValueInToken2;

        // Approve Uniswap router to spend USDC
        IERC20(I_TOKEN2).approve(address(I_UNISWAP_V2_ROUTER_02), maxTokenToSend);

        I_UNISWAP_V2_ROUTER_02.swapExactTokensForETH({
            amountIn: maxTokenToSend,
            amountOutMin: minEthToRecieve,
            path: sToken2ToToken1Path,
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
        sAllocationState = AllocationState.AFTER_DEPOSIT;
    }

    function withdraw() external onlyOwner {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        require(success, "Transfer failed");
        // Add a way to withdraw the token
    }
}
