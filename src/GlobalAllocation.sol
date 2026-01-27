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
    uint8 private immutable I_TOKEN2_DECIMALS;

    uint256 private sEthPortfolioBalanceInToken2;
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
            _desiredEthToTokenAllocationPercentage >= 1e4 && _desiredEthToTokenAllocationPercentage <= 1e6,
            "Allocation percentage must be between 1.0000% and 100.0000%"
        );
        require(
            _rebalancePercentage >= 1e3 && _rebalancePercentage <= 1e5,
            "Rebalance percentage must be between 0.1000% and 10.0000%"
        );

        I_TOKEN1 = _token1;
        I_TOKEN2 = _token2;
        I_UNISWAP_V2_ROUTER_02 = IUniswapV2Router02(_uniswapRouter);
        sToken1ToToken2Path = [I_TOKEN1, I_TOKEN2];
        sToken2ToToken1Path = [I_TOKEN2, I_TOKEN1];
        desiredEthToTokenAllocationPercentage = _desiredEthToTokenAllocationPercentage;
        rebalancePercentage = _rebalancePercentage;
        I_TOKEN2_DECIMALS = IERC20Metadata(I_TOKEN2).decimals();
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
        // Update state
        sAllocationState = AllocationState.AFTER_ETH_QUOTE;
    }

    /**
     * @dev Update Portfolio based on most recently quoted token2 value
     */
    function updateCurrentAllocationPercentage() public {
        sEthPortfolioBalanceInToken2 = sEthPriceInToken2 * address(this).balance / 1e18;
        sTotalPortfolioValueInToken2 = sEthPortfolioBalanceInToken2 + IERC20Metadata(I_TOKEN2).balanceOf(address(this));

        if (address(this).balance == 0) {
            currentEthToTokenAllocationPercentage = 0;
            return;
        } else {
            require(
                sEthPortfolioBalanceInToken2 * 1e6 / sTotalPortfolioValueInToken2 < type(uint24).max,
                "Value will be truncated when type casting"
            );
            // casting to 'uint24' is safe because require statement above ensures value ≤ type(uint24).max
            // forge-lint: disable-next-line(unsafe-typecast)
            currentEthToTokenAllocationPercentage =
                uint24(sEthPortfolioBalanceInToken2 * 1e6 / sTotalPortfolioValueInToken2);
        }

        // console2.log("Eth price in token2", sEthPriceInToken2);
        // console2.log("Contract Eth balance", address(this).balance);
        // console2.log("Eth balance in token2", sEthPortfolioBalanceInToken2);
        // console2.log("Contract token2 balance", IERC20Metadata(I_TOKEN2).balanceOf(address(this)));
        // console2.log("Total portfolio balnce in token2", sTotalPortfolioValueInToken2); // 6 decimals
        // console2.log("Eth To Token2 allocation percentage", currentEthToTokenAllocationPercentage); // 4 decimals

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
            * sTotalPortfolioValueInToken2 / (10 ** I_TOKEN2_DECIMALS);

        // Use quoted price to send set a max eth willing to pay for transaction to go through
        uint256 maxEthToSend = (minTokenToRecieve * 1e18) / sEthPriceInToken2;

        // console2.log("Total Portfolio Value in Token2", sTotalPortfolioValueInToken2);
        // console2.log("Current allocation percentage", currentEthToTokenAllocationPercentage);
        // console2.log("Desired allocation percentage", desiredEthToTokenAllocationPercentage);
        // console2.log("Min token to receive", minTokenToRecieve);

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
        uint24 slippage = 10000; // 01.0000%
        uint256 maxTokenToSend = (desiredEthToTokenAllocationPercentage - currentEthToTokenAllocationPercentage)
            * sTotalPortfolioValueInToken2 / (10 ** I_TOKEN2_DECIMALS);

        // Use quoted price to set a min eth received for transaction to go through
        uint256 minEthToRecieve = (maxTokenToSend * 1e18) / sEthPriceInToken2;

        console2.log("Total Portfolio Value in Token2", sTotalPortfolioValueInToken2);
        console2.log("Current allocation percentage", currentEthToTokenAllocationPercentage);
        console2.log("Desired allocation percentage", desiredEthToTokenAllocationPercentage);
        console2.log("Max token to send", maxTokenToSend);
        console2.log("Min Eth to receive", minEthToRecieve);

        // Approve Uniswap router to spend USDC
        IERC20Metadata(I_TOKEN2).approve(address(I_UNISWAP_V2_ROUTER_02), maxTokenToSend);

        I_UNISWAP_V2_ROUTER_02.swapExactTokensForETH({
            amountIn: maxTokenToSend,
            amountOutMin: (minEthToRecieve * (1e6 - slippage)) / 1e6,
            path: sToken2ToToken1Path,
            to: address(this),
            deadline: block.timestamp + 15 minutes
        });
    }

    /**
     * @dev Accept ETH deposits
     */
    receive() external payable {
        require(msg.value > 0, "Must send ETH to deposit");

        // Setting post deposit state so the next re-balance uses Chainlink price feed instead of Uniswap quote
        sAllocationState = AllocationState.AFTER_DEPOSIT;
    }

    /**
     * @dev Accept token2 deposits
     * @param _amount Amount of token2 to transfer from user's wallet to this contract
     * @return success Boolean indicating if the transfer was successful
     */
    function depositToken2(uint256 _amount) public returns (bool success) {
        require(_amount > 0, "Must deposit a positive amount");

        // Transfer token2 from msg.sender to this contract
        success = IERC20Metadata(I_TOKEN2).transferFrom(msg.sender, address(this), _amount);
        require(success, "Token2 transfer failed");

        // Setting post deposit state so the next re-balance uses appropriate price feed
        sAllocationState = AllocationState.AFTER_DEPOSIT;
    }

    /**
     * @dev Allow user to withdraw all funds from the contract
     */
    function withdraw() external onlyOwner {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        require(success, "Eth withdraw failed");

        success = IERC20Metadata(I_TOKEN2).transfer(msg.sender, IERC20Metadata(I_TOKEN2).balanceOf(address(this)));
        require(success, "Token withdraw failed");
    }
}
