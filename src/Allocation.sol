// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {IUniswapV2Router02} from "@uniswap-v2-per/interfaces/IUniswapV2Router02.sol";

contract Allocation {
    /* Global Variables */
    uint256 private ethToUsdcAllocation; // percentage allocation for ETH, number between 0-100
    address public token; //Specify token, will be USDC address on deployment
    address[] public users;
    IUniswapV2Router02 public uniswapV2Router02 = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D); // Uniswap V2 Router address on Ethereum mainnet

    /* Mappings */
    mapping (address => uint256[2]) public userBalancesEthUsdc; // mapping to store user balances [ethBalance, usdcBalance]


    constructor(address _token, uint256 _ethToUsdcAllocation) {
        token = _token;
        ethToUsdcAllocation = _ethToUsdcAllocation;
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

    function setEthToUsdcAllocation(uint256 _allocation) external {
        require(_allocation <= 100 && _allocation > 0, "Allocation must be between 0 and 100");
        ethToUsdcAllocation = _allocation;
    }

    function getEthToUsdcAllocation() external view returns (uint256) {
        return ethToUsdcAllocation;
    }

    function getMyBalance() external view returns (uint256 ethBalance, uint256 usdcBalance) {
        ethBalance = userBalancesEthUsdc[msg.sender][0];
        usdcBalance = userBalancesEthUsdc[msg.sender][1];
    }


}
