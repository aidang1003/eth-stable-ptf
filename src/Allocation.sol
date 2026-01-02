// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

contract Allocation {
    uint256 private ethToUsdcAllocation; // percentage allocation for ETH, number between 0-100

    address public token; //Specify token, will be USDC address on deployment

    mapping (address => uint256) public userEthBalances;
    mapping (address => uint256) public userUsdcBalances;

    constructor(address _token, uint256 _ethToUsdcAllocation) {
        token = _token;
        ethToUsdcAllocation = _ethToUsdcAllocation;
    }

    /** Fund the contract by sending eth or calling depositToken() */
    receive() external payable {
        // Send eth to contract to fund
        userEthBalances[msg.sender] += msg.value;
    }

    function depositToken(uint256 _amount) public payable {
        // Deposit USDC tokens to the contract
        require(_amount > 0, "Amount must be greater than 0");
        bool transferred = IERC20(token).transferFrom(msg.sender, address(this), _amount);
        require(transferred, "Token transfer failed");
        userUsdcBalances[msg.sender] += _amount;
    }

    // Create a function that calls a limit swap from uniswap

    // Create a function to withdraw tokens
    function withdrawAllTokens(address _token) external {
        require(userEthBalances[msg.sender] >= 0, "Insufficient ETH balance");
        require(userUsdcBalances[msg.sender] >= 0, "Insufficient USDC balance");
        IERC20(_token).transfer(msg.sender, userUsdcBalances[msg.sender]);
        userUsdcBalances[msg.sender] = 0;
        (bool sent, /* bytes memory data */) = msg.sender.call{value: userEthBalances[msg.sender]}("");
        require(sent, "Failed to send Ether");
        userEthBalances[msg.sender] = 0;
    }

    function setEthToUsdcAllocation(uint256 _allocation) external {
        require(_allocation <= 100 && _allocation > 0, "Allocation must be between 0 and 100");
        ethToUsdcAllocation = _allocation;
    }

    function getEthToUsdcAllocation() external view returns (uint256) {
        return ethToUsdcAllocation;
    }


}
