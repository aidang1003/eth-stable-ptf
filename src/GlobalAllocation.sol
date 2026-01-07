// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract GlobalAllocation is Ownable(msg.sender) {
    uint24 public desiredEthToUsdcAllocationPerccentage; // percentage allocation for ( ETH(in USD) / ETH(in USD) * USDC ) * 1000000, number 1.0000%-100.0000%
    uint24 public rebalancePercentage; // percentage of the portfolio to rebalance at a time

    constructor(uint24 _desiredEthToUsdcAllocationPerccentage, uint24 _rebalancePercentage) {
        require(_desiredEthToUsdcAllocationPerccentage <= 1000000 && _desiredEthToUsdcAllocationPerccentage >= 10000, "Allocation percentage must be between 1.0000% and 100.0000%");
        require(_rebalancePercentage <= 100000 && _rebalancePercentage >= 1000, "Rebalance percentage must be between 0.1000% and 10.0000%");

        desiredEthToUsdcAllocationPerccentage = _desiredEthToUsdcAllocationPerccentage;
        rebalancePercentage = _rebalancePercentage;
    }

    receive() external payable {
        // Accept ETH deposits
        require(msg.value > 0, "Must send ETH to deposit");


    }

    function withdraw() external onlyOwner{
        // Placeholder for withdraw function
    }
}