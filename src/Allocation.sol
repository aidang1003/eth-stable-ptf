// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

contract Allocation {
    uint256 private ethToUsdcAllocation; // percentage allocation for ETH, number between 0-100
    // Create a function that calls a limit swap from uniswap

    // Create a function that takes in ETH/USDC

    // Create a function to withdraw tokens
    function withdrawTokens(address _token, uint256 _amount) external {
        IERC20(_token).transfer(msg.sender, _amount);
    }

    function setEthToUsdcAllocation(uint256 _allocation) external {
        require(_allocation <= 100 && _allocation > 0, "Allocation must be between 0 and 100");
        ethToUsdcAllocation = _allocation;
    }

    function getEthToUsdcAllocation() external view returns (uint256) {
        return ethToUsdcAllocation;
    }

}
