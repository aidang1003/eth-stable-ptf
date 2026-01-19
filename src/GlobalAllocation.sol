// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {UNISWAP_V2_ROUTER02} from "./Constants.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract GlobalAllocation is Ownable {
    uint24 public desiredEthToUsdcAllocationPerccentage; // percentage allocation for ( ETH(in USD) / ETH(in USD) * USDC ) * 1000000, number 1.0000%-100.0000%
    uint24 public currentEthToUsdcAllocationPercentage; // percentage allocation for ( ETH(in USD) / ETH(in USD) * USDC ) * 1000000, number 0%-100.0000%
    uint24 public immutable rebalancePercentage; // percentage of the portfolio to rebalance at a time

    /* State Variables */
    address private immutable i_token1; // Specify token1 address (ETH)
    address private immutable i_token2; // Specify token2 address (USDT)
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
    }

    /**
     * @dev Swaps ETH for token address using Uniswap
     */
    function swapEthForToken() internal {
        // Fix the math here
        uint256 maxEthToSend = (address(this).balance * rebalancePercentage) / 1000000;
        uint256 minTokenToRecieve = (returnAmounts[1] * (1000000 - rebalancePercentage)) / 1000000;

        returnAmounts = uniswapV2Router02.swapExactETHForTokens{value: maxEthToSend}({
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
        require(
            desiredEthToUsdcAllocationPerccentage > currentEthToUsdcAllocationPercentage,
            "Desired Eth allocation less than current Eth allocation"
        );
        uint256 maxTokenToSend = (desiredEthToUsdcAllocationPerccentage - currentEthToUsdcAllocationPercentage)
            * IERC20(i_token2).balanceOf(address(this)) / 100000;
        // uint256 minEthToRecieve = ;

        // Approve Uniswap router to spend USDC
        IERC20(i_token2).approve(address(uniswapV2Router02), maxTokenToSend);

        returnAmounts = uniswapV2Router02.swapExactTokensForETH({
            amountIn: maxTokenToSend,
            amountOutMin: 0, // Verify this works with 0, then calculate acceptable slippage for real value
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
        // Accept ETH deposits
        require(msg.value > 0, "Must send ETH to deposit");
        // balanceFunds();
    }

    function withdraw() external onlyOwner {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }
}
