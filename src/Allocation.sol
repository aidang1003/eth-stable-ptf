// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {UNISWAP_V2_ROUTER02, UNISWAP_V2_PAIR_ETH_USDC, WETH_ADDRESS, USDC_ADDRESS} from "./Constants.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {console2} from "forge-std/console2.sol";

contract Allocation {
    /* Global Variables */
    uint256 private ethToUsdcAllocationPercentage; // percentage allocation for ( ETH(in USD) / ETH(in USD) * USDC ) * 100, number between 0-100
    address public token; //Specify token, will be USDC address on deployment
    address[] public users;
    IUniswapV2Router02 public uniswapV2Router02 = IUniswapV2Router02(UNISWAP_V2_ROUTER02); // Uniswap V2 Router address on Ethereum mainnet

    /* Mappings */
    mapping (address => uint256[2]) private userBalancesEthUsdc; // mapping to store user balances [ethBalance, usdcBalance]


    constructor(address _token, uint256 _ethToUsdcAllocationPercentage) {
        token = _token;
        ethToUsdcAllocationPercentage = _ethToUsdcAllocationPercentage;
    }

    /** Fund the contract by sending eth or calling depositToken() */
    receive() external payable {
        // Send eth to contract to fund
        userBalancesEthUsdc[msg.sender][0] += msg.value;
    }

    function depositToken(uint256 _amount) public payable {
        // Deposit USDC tokens to the contract
        require(_amount > 0, "Amount must be greater than 0");

        // Add user to users array if not already present
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] == msg.sender) {
                return;
            } if (i == users.length - 1) {
                users.push(msg.sender);
            } else {
                continue;
            }
        }
        
        bool transferred = IERC20(token).transferFrom(msg.sender, address(this), _amount);
        require(transferred, "Token transfer failed");
        userBalancesEthUsdc[msg.sender][1] += _amount;
    }

    // Create a function that balance a user's allocation immeditley with a call to the uniswap v2 periphery contract
    function balanceAllocation(address _user) public {
        require(userBalancesEthUsdc[_user][0] >= 0 || userBalancesEthUsdc[_user][1] >= 0, "Insufficient ETH or USDC balance");
        address[] memory path = new address[](2);
        uint256[] memory returnAmounts = new uint256[](path.length);
        uint256 usdcValueOfEth = 0;

        // Get the Eth conversion rate for USDC from Uniswap
        if (userBalancesEthUsdc[_user][0] > 0) {
            path[0] = WETH_ADDRESS;
            path[1] = USDC_ADDRESS;
            uint[] memory amounts = uniswapV2Router02.getAmountsOut(userBalancesEthUsdc[_user][0], path);

            // Eth in portfolio represented in USDC
            usdcValueOfEth = amounts[1];
            console2.log("(amounts[1]) Estimated USDC from ETH:", usdcValueOfEth);
        } 
        
        uint256 totalPortfolioValue = userBalancesEthUsdc[_user][1] + usdcValueOfEth;
        console2.log("Total portfolio value in USDC:", totalPortfolioValue);
        
        if ((usdcValueOfEth / totalPortfolioValue) * 100 > ethToUsdcAllocationPercentage) {
        // If the user has more ETH than the desired allocation, swap ETH for USDC
            uint256 minUsdcToRecieve = (usdcValueOfEth * ethToUsdcAllocationPercentage / 100) - (userBalancesEthUsdc[_user][1] * 100 / totalPortfolioValue);
            console2.log("ETH to swap for USDC:", minUsdcToRecieve);

            require(minUsdcToRecieve > 0, "No ETH to swap for USDC");

            path[0] = WETH_ADDRESS;
            path[1] = USDC_ADDRESS;

            IERC20(WETH_ADDRESS).approve(address(uniswapV2Router02), minUsdcToRecieve);
            returnAmounts = uniswapV2Router02.swapExactETHForTokens{value: 5e17}({
                amountOutMin: minUsdcToRecieve,
                path: path,
                to: address(this),
                deadline: block.timestamp + 15 minutes
            });
        } else if ((usdcValueOfEth / totalPortfolioValue) * 100 > ethToUsdcAllocationPercentage) {
        // If the user has more USDC than the desired allocation, swap USDC for ETH
            uint256 usdcToSwap = (userBalancesEthUsdc[_user][1] * 100 / totalPortfolioValue) - (usdcValueOfEth * ethToUsdcAllocationPercentage / 100);
            console2.log("USDC to swap for ETH:", usdcToSwap);

            require(usdcToSwap > 0, "No USDC to swap for ETH");

            path[0] = USDC_ADDRESS;
            path[1] = WETH_ADDRESS;

            IERC20(USDC_ADDRESS).approve(address(uniswapV2Router02), usdcToSwap);
            returnAmounts = uniswapV2Router02.swapTokensForExactTokens({
                amountOut: usdcToSwap,
                amountInMax: 0, // verify this works with 0, then calculate acceptable slippage for real value
                path: path,
                to: address(this),
                deadline: block.timestamp + 15 minutes
            });
        } else {
            console2.log("User allocation is already withing an acceptable range or you have an arithmetic/logic error");
            return;
        }
    }

    // Create a function to withdraw tokens
    function withdrawAllTokens(address _token) external {
        require(userBalancesEthUsdc[msg.sender][0] >= 0, "Insufficient ETH balance");
        require(userBalancesEthUsdc[msg.sender][1] >= 0, "Insufficient USDC balance");

        // withdraw USDC
        bool transferred = IERC20(_token).transfer(msg.sender, userBalancesEthUsdc[msg.sender][1]);
        require(transferred, "Token transfer failed");
        userBalancesEthUsdc[msg.sender][1] = 0;

        // withdraw ETH
        (bool sent, /* bytes memory data */) = msg.sender.call{value: userBalancesEthUsdc[msg.sender][0]}("");
        require(sent, "Failed to send Ether");
        userBalancesEthUsdc[msg.sender][0] = 0;
    }

    function setethToUsdcAllocationPercentage(uint256 _allocation) external {
        require(_allocation <= 100 && _allocation > 0, "Allocation must be between 0 and 100");
        ethToUsdcAllocationPercentage = _allocation;
    }

    function getethToUsdcAllocationPercentage() external view returns (uint256) {
        return ethToUsdcAllocationPercentage;
    }

    function getMyBalance() external view returns (uint256 ethBalance, uint256 usdcBalance) {
        ethBalance = userBalancesEthUsdc[msg.sender][0];
        usdcBalance = userBalancesEthUsdc[msg.sender][1];
    }


}
