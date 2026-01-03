// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {UNISWAP_V2_ROUTER02, UNISWAP_V2_PAIR_ETH_USDC, WETH_ADDRESS, USDC_ADDRESS} from "./Constants.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {console2} from "forge-std/console2.sol";

contract Allocation {
    /* Internal Global Variables */
    uint24 private ethToUsdcAllocationPercentage; // percentage allocation for ( ETH(in USD) / ETH(in USD) * USDC ) * 100, number between 0-100
    uint24 private currentEthToUsdcAllocationPercentage;
    address[] private path = new address[](2);
    uint256[] private returnAmounts = new uint256[](path.length);
    uint256 usdcValueOfEth = 0;
    uint256 private totalPortfolioValueInUsdc;

    /* Global variables (external) */
    address[] public users;
    address public token; //Specify token, will be USDC address on deployment
    IUniswapV2Router02 public uniswapV2Router02 = IUniswapV2Router02(UNISWAP_V2_ROUTER02); // Uniswap V2 Router address on Ethereum mainnet

    /* Mappings */
    mapping (address => uint256[2]) private userBalancesEthUsdc; // mapping to store user balances [ethBalance, usdcBalance]


    constructor(address _token, uint24 _ethToUsdcAllocationPercentage) {
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

    function updateCurrentAllocationPercentage(address _user) public {
        // Get the Eth conversion rate for USDC from Uniswap
        // Set the Eth value in USDC, total portfolio value in USDC, and current allocation percentage
        if (userBalancesEthUsdc[_user][0] > 0) {
            (path[0], path[1]) = (WETH_ADDRESS, USDC_ADDRESS);

            uint[] memory amounts = uniswapV2Router02.getAmountsOut(userBalancesEthUsdc[_user][0], path);
            usdcValueOfEth = amounts[1]; // Eth in portfolio represented in USDC
            totalPortfolioValueInUsdc = usdcValueOfEth + userBalancesEthUsdc[_user][1];
            currentEthToUsdcAllocationPercentage = uint24((usdcValueOfEth * 100) / (usdcValueOfEth + userBalancesEthUsdc[_user][1]));
        } else {
            totalPortfolioValueInUsdc = userBalancesEthUsdc[_user][1];
            currentEthToUsdcAllocationPercentage = 0;
        }
        
        console2.log("Current ETH to USDC allocation percentage:", currentEthToUsdcAllocationPercentage);
    }

    // Create a function that balance a user's allocation immeditley with a call to the uniswap v2 periphery contract
    function balanceAllocation(address _user) public {
        require(userBalancesEthUsdc[_user][0] >= 0 || userBalancesEthUsdc[_user][1] >= 0, "Insufficient ETH or USDC balance");
        
        // Call function to update current allocation percentage
        updateCurrentAllocationPercentage(_user);
        
        // Make swaps based on current vs desired allocation percentage
        if (currentEthToUsdcAllocationPercentage > ethToUsdcAllocationPercentage) {
        // If the user has more ETH than the desired allocation, swap ETH for USDC
            uint256 maxEthToSend = userBalancesEthUsdc[_user][0] * ethToUsdcAllocationPercentage / 100; //Won't work for all values
            uint256 minUsdcToRecieve = (usdcValueOfEth * ethToUsdcAllocationPercentage / 100) - (userBalancesEthUsdc[_user][1] * 100 / totalPortfolioValueInUsdc);
            console2.log("ETH to swap for USDC: %e", minUsdcToRecieve);

            require(minUsdcToRecieve > 0, "No ETH to swap for USDC");

            (path[0], path[1]) = (WETH_ADDRESS, USDC_ADDRESS);

            IERC20(WETH_ADDRESS).approve(address(uniswapV2Router02), minUsdcToRecieve);
            returnAmounts = uniswapV2Router02.swapExactETHForTokens{value: maxEthToSend}({
                amountOutMin: minUsdcToRecieve,
                path: path,
                to: address(this),
                deadline: block.timestamp + 15 minutes
            });
        } else if (currentEthToUsdcAllocationPercentage < ethToUsdcAllocationPercentage) {
        // If the user has more USDC than the desired allocation, swap USDC for ETH
            uint256 usdcToSwap = (ethToUsdcAllocationPercentage - currentEthToUsdcAllocationPercentage) * userBalancesEthUsdc[_user][1] / 100;
            console2.log("USDC to swap for ETH: %e", usdcToSwap);

            require(usdcToSwap > 0, "No USDC to swap for ETH");

            (path[0], path[1]) = (USDC_ADDRESS, WETH_ADDRESS);

            IERC20(USDC_ADDRESS).approve(address(uniswapV2Router02), usdcToSwap);
            returnAmounts = uniswapV2Router02.swapExactTokensForETH({ 
                amountIn: usdcToSwap,
                amountOutMin: 0, // Verify this works with 0, then calculate acceptable slippage for real value
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

    function setEthToUsdcAllocationPercentage(uint24 _allocation) external {
        require(_allocation <= 100 && _allocation > 0, "Allocation must be between 0 and 100");
        ethToUsdcAllocationPercentage = _allocation;
    }

    function getEthToUsdcAllocationPercentage() external view returns (uint256) {
        return ethToUsdcAllocationPercentage;
    }

    function getMyBalance() external view returns (uint256 ethBalance, uint256 usdcBalance) {
        ethBalance = userBalancesEthUsdc[msg.sender][0];
        usdcBalance = userBalancesEthUsdc[msg.sender][1];
    }


}
