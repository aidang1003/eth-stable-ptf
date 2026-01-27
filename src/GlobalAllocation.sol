// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import {console2} from "forge-std/console2.sol";

contract GlobalAllocation is Ownable {
    uint24 public desiredEthToTokenAllocationPercentage; // percentage allocation for ( ETH(in USD) / ETH(in USD) * USDC ) * 1000000, number 1.0000%-100.0000%
    uint24 public currentEthToTokenAllocationPercentage; // percentage allocation for ( ETH(in USD) / ETH(in USD) * USDC ) * 1000000, number 0%-100.0000%
    uint24 public rebalancePercentage; // percentage threshold of when to reset the allocation percentages

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
    uint8 private I_Token2Decimals;

    uint256 private sTotalPortfolioValueInToken2;
    uint256 private sEthPriceInToken2; // Value of 1 Ether in terms of token2 according to Uniswap quote
    address[] private sToken1ToToken2Path;
    address[] private sToken2ToToken1Path;
    AllocationState private sAllocationState;

    IUniswapV2Router02 private immutable I_UNISWAP_V2_ROUTER_02;

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
        I_TOKEN2 = _token2;
        I_UNISWAP_V2_ROUTER_02 = IUniswapV2Router02(_uniswapRouter);
        sToken1ToToken2Path = [I_TOKEN1, I_TOKEN2];
        sToken2ToToken1Path = [I_TOKEN2, I_TOKEN1];
        desiredEthToTokenAllocationPercentage = _desiredEthToTokenAllocationPercentage;
        rebalancePercentage = _rebalancePercentage;
        I_Token2Decimals = IERC20Metadata(I_TOKEN2).decimals();
    }

    /**
     * @dev Updates the current allocation percentage based on Uniswap quoted Eth price
     * If immediatley after deposit use ChainLink Pricefeed to get ETH value in token2 terms
     * The Chainlink value is to ensure that the Uniswap price quote is reasonable when performing a larger transaction
     * Use a Uniswap quote to get ETH value in token2 terms
     */
    function quoteEthPriceInToken2() public {
        uint256[] memory returnAmounts = I_UNISWAP_V2_ROUTER_02.getAmountsOut(1 ether, sToken1ToToken2Path);
        sEthPriceInToken2 = returnAmounts[1];
        console2.log("Eth price in token 2 Uni quote:", sEthPriceInToken2);

        // Update state
        sAllocationState = AllocationState.AFTER_ETH_QUOTE;
    }

    /**
     * @dev Update Portfolio based on most recently quoted token2 value
     */
    function updateCurrentAllocationPercentage() public {
        sTotalPortfolioValueInToken2 =
            (sEthPriceInToken2 * address(this).balance) + IERC20Metadata(I_TOKEN2).balanceOf(address(this));

        if (address(this).balance == 0) {
            currentEthToTokenAllocationPercentage = 0;
            return;
        } else {
            require(
                (sEthPriceInToken2 * 1000000) / sTotalPortfolioValueInToken2 < type(uint24).max,
                "Value will be truncated when type casting"
            );
            // casting to 'uint24' is safe because require statement above ensures value ≤ type(uint24).max
            // forge-lint: disable-next-line(unsafe-typecast)
            currentEthToTokenAllocationPercentage = uint24((sEthPriceInToken2 * 1000000) / sTotalPortfolioValueInToken2);
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
        if (currentEthToTokenAllocationPercentage < desiredEthToTokenAllocationPercentage) {
            swapTokenForEth();
        } else if (currentEthToTokenAllocationPercentage > desiredEthToTokenAllocationPercentage) {
            swapEthForToken();
        } else {
            return;
        }
    }

    /**
     * @dev Swaps ETH for token address using Uniswap
     */
    function swapEthForToken() internal {
        uint256 minTokenToRecieve = (currentEthToTokenAllocationPercentage - desiredEthToTokenAllocationPercentage)
            * sTotalPortfolioValueInToken2 / 1000000 / (10 ** I_Token2Decimals);

        // Use quoted price to send the max eth required for transaction to go through
        uint256 maxEthToSend = minTokenToRecieve / sEthPriceInToken2 / (10 ** I_Token2Decimals);

        // console2.log(
        //     "current alloc - desired alloc",
        //     currentEthToTokenAllocationPercentage - desiredEthToTokenAllocationPercentage
        // );
        console2.log("total portfolio value in token2 terms:", sTotalPortfolioValueInToken2);
        console2.log("Eth Value in token terms:", sEthPriceInToken2);
        console2.log("Min Token:", minTokenToRecieve);
        console2.log("Max Eth:", maxEthToSend);

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
        uint256 maxTokenToSend = (desiredEthToTokenAllocationPercentage - currentEthToTokenAllocationPercentage)
            * sTotalPortfolioValueInToken2 / 100000;
        uint256 minEthToRecieve = maxTokenToSend / sEthPriceInToken2;

        // Approve Uniswap router to spend USDC
        IERC20Metadata(I_TOKEN2).approve(address(I_UNISWAP_V2_ROUTER_02), maxTokenToSend);

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
        require(success, "Eth withdraw failed");

        success = IERC20Metadata(I_TOKEN2).transfer(msg.sender, IERC20Metadata(I_TOKEN2).balanceOf(address(this)));
        require(success, "Token withdraw failed");
    }
}
