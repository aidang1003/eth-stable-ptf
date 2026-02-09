// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
// import {console2} from "forge-std/console2.sol";
import {GlobalAllocation} from "../../src/GlobalAllocation.sol";
import {DeployGlobalAllocation} from "../../script/DeployGlobalAllocation.s.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

contract GlobalAllocationTest is Test {
    HelperConfig public helperConfig;

    address public wethAddress;
    address public usdcAddress;
    address public uniswapV2Router02;

    GlobalAllocation public globalAllocation;
    IERC20 public token2;

    address public user;
    uint256 public constant INITIAL_DEPOSIT = 1 ether;

    function setUp() public {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        wethAddress = config.token1;
        usdcAddress = config.token2;
        uniswapV2Router02 = config.uniswapRouter;
        token2 = IERC20(usdcAddress);

        user = config.senderAddress;
        vm.deal(user, 10 ether);

        DeployGlobalAllocation deployGlobalAllocation = new DeployGlobalAllocation();
        globalAllocation = deployGlobalAllocation.deployContract();

        vm.startPrank(user);

        // Fund the contract with initial ETH deposit
        (bool success,) = address(globalAllocation).call{value: INITIAL_DEPOSIT}("");
        require(success, "Initial deposit failed");

        // Approve contract to spend user's USDC
        token2.approve(address(globalAllocation), type(uint256).max);

        vm.stopPrank();
    }

    function testDeposit() public {
        vm.startPrank(user);

        uint256 additionalDeposit = 0.5 ether;
        uint256 balanceBefore = address(globalAllocation).balance;

        // Deposit additional ETH to the contract
        (bool success,) = address(globalAllocation).call{value: additionalDeposit}("");
        require(success, "Deposit failed");

        // Verify the contract received the ETH
        assertEq(
            address(globalAllocation).balance,
            balanceBefore + additionalDeposit,
            "Contract balance should increase by deposit amount"
        );

        vm.stopPrank();
    }

    function testWithdraw() public {
        vm.startPrank(user);

        // Record balances before withdrawal
        uint256 contractBalanceBefore = address(globalAllocation).balance;
        uint256 userBalanceBefore = user.balance;

        // Withdraw all funds from the contract
        globalAllocation.withdraw();

        // Verify the contract balance is now 0
        assertEq(address(globalAllocation).balance, 0, "Contract balance should be 0 after withdrawal");

        // Verify user received the withdrawn funds
        assertEq(
            user.balance, userBalanceBefore + contractBalanceBefore, "User balance should increase by withdrawn amount"
        );

        vm.stopPrank();
    }

    function testRebalanceAndThenWithdraw() public {
        vm.startPrank(user);

        // First rebalance to swap some ETH for USDC
        globalAllocation.balanceFundsExternal();

        // Record balances after rebalance
        uint256 contractEthBalance = address(globalAllocation).balance;
        uint256 contractUsdcBalance = token2.balanceOf(address(globalAllocation));
        uint256 userEthBalanceBefore = user.balance;
        uint256 userUsdcBalanceBefore = token2.balanceOf(user);

        // Verify contract has both ETH and USDC after rebalance
        assertGt(contractEthBalance, 0, "Contract should have ETH after rebalance");
        assertGt(contractUsdcBalance, 0, "Contract should have USDC after rebalance");

        // Withdraw all funds
        globalAllocation.withdraw();

        // Verify contract balances are now 0
        assertEq(address(globalAllocation).balance, 0, "Contract ETH balance should be 0 after withdrawal");
        assertEq(token2.balanceOf(address(globalAllocation)), 0, "Contract USDC balance should be 0 after withdrawal");

        // Verify user received both ETH and USDC
        assertEq(user.balance, userEthBalanceBefore + contractEthBalance, "User should receive all ETH from contract");
        assertEq(
            token2.balanceOf(user),
            userUsdcBalanceBefore + contractUsdcBalance,
            "User should receive all USDC from contract"
        );

        vm.stopPrank();
    }

    function testSwapEthForToken() public {
        vm.startPrank(user);

        // Record balances before swap
        uint256 ethBalanceBefore = address(globalAllocation).balance;
        uint256 usdcBalanceBefore = token2.balanceOf(address(globalAllocation));

        // Trigger the swap by calling balanceFundsExternal
        // This will call swapEthForToken since all funds are in ETH (currentAllocation > desiredAllocation)
        globalAllocation.balanceFundsExternal();

        // Get balances after swap
        uint256 ethBalanceAfter = address(globalAllocation).balance;
        uint256 usdcBalanceAfter = token2.balanceOf(address(globalAllocation));

        // Verify ETH balance decreased
        assertLt(ethBalanceAfter, ethBalanceBefore, "ETH balance should decrease after swap");

        // Verify USDC balance increased
        assertGt(usdcBalanceAfter, usdcBalanceBefore, "USDC balance should increase after swap");

        vm.stopPrank();
    }

    function testSwapTokenForEth() public {
        vm.startPrank(user);

        // Withdraw all ETH from the contract to start fresh
        globalAllocation.withdraw();

        // Verify contract has no ETH
        assertEq(address(globalAllocation).balance, 0, "Contract should have no ETH after withdrawal");

        uint256 usdcAmount = 1000e6; // $1,000 USDC (6 decimals)
        deal(usdcAddress, user, usdcAmount);

        // Deposit USDC to the contract
        bool success = globalAllocation.depositToken2(usdcAmount);
        require(success, "USDC deposit failed");

        // Verify contract has USDC and no ETH
        assertEq(token2.balanceOf(address(globalAllocation)), usdcAmount, "Contract should have $10k USDC");
        assertEq(address(globalAllocation).balance, 0, "Contract should still have no ETH");

        // Record balances before swap
        uint256 ethBalanceBefore = address(globalAllocation).balance;
        uint256 usdcBalanceBefore = token2.balanceOf(address(globalAllocation));

        // Trigger the swap by calling balanceFundsExternal
        // This will call swapTokenForEth since we only have USDC (currentAllocation < desiredAllocation)
        globalAllocation.balanceFundsExternal();

        // Get balances after swap
        uint256 ethBalanceAfter = address(globalAllocation).balance;
        uint256 usdcBalanceAfter = token2.balanceOf(address(globalAllocation));

        // Verify USDC balance decreased
        assertLt(usdcBalanceAfter, usdcBalanceBefore, "USDC balance should decrease after swap");

        // Verify ETH balance increased
        assertGt(ethBalanceAfter, ethBalanceBefore, "ETH balance should increase after swap");

        vm.stopPrank();
    }

    function testRebalanceRevertsWhenEthHigherWithinThreshold() public {
        vm.startPrank(user);

        // First, balance the funds so we're at the desired allocation
        globalAllocation.balanceFundsExternal();

        // Verify we now have both ETH and USDC (meaning we're balanced)
        uint256 ethBalance = address(globalAllocation).balance;
        uint256 usdcBalance = token2.balanceOf(address(globalAllocation));
        assertGt(ethBalance, 0, "Should have ETH after first balance");
        assertGt(usdcBalance, 0, "Should have USDC after first balance");

        // Fund the contract with initial ETH deposit
        (bool success,) = address(globalAllocation).call{value: 6e16}(""); // 0.06 ether
        require(success, "Deposit failed");

        // Now try to rebalance again - should revert since we're within threshold
        // This tests the absolute difference check works when current ≈ desired
        vm.expectRevert("Allocation__ReAllocationNotNeeded()");
        globalAllocation.balanceFundsExternal();

        vm.stopPrank();
    }

    function testRebalanceRevertsWhenUsdHigherWithinThreshold() public {
        vm.startPrank(user);

        // First, balance the funds so we're at the desired allocation
        globalAllocation.balanceFundsExternal();

        // Verify we now have both ETH and USDC (meaning we're balanced)
        uint256 ethBalance = address(globalAllocation).balance;
        uint256 usdcBalance = token2.balanceOf(address(globalAllocation));
        assertGt(ethBalance, 0, "Should have ETH after first balance");
        assertGt(usdcBalance, 0, "Should have USDC after first balance");

        // Fund the contract with initial ETH deposit
        bool success = globalAllocation.depositToken2(1e8); // $100
        require(success, "USDC deposit failed");

        // Now try to rebalance again - should revert since we're within threshold
        // This tests the absolute difference check works when current ≈ desired
        vm.expectRevert("Allocation__ReAllocationNotNeeded()");
        globalAllocation.balanceFundsExternal();

        vm.stopPrank();
    }

    function testSwapTokenForEthWithWhale() public {
        vm.startPrank(user);

        // First swap ETH for USDC to have both assets in the contract
        globalAllocation.balanceFundsExternal();

        // Verify we have both ETH and USDC
        uint256 usdcAfterFirstSwap = token2.balanceOf(address(globalAllocation));
        uint256 ethAfterFirstSwap = address(globalAllocation).balance;
        assertGt(usdcAfterFirstSwap, 0, "Should have USDC after first swap");
        assertGt(ethAfterFirstSwap, 0, "Should have ETH after first swap");

        vm.stopPrank();

        // Query actual pool reserves to derive a realistic whale swap amount
        IUniswapV2Router02 router = IUniswapV2Router02(uniswapV2Router02);
        address factory = router.factory();
        address pair = IUniswapV2Factory(factory).getPair(wethAddress, usdcAddress);
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();

        // Determine which reserve is WETH (token0 is the lower address)
        uint256 wethReserve = IUniswapV2Pair(pair).token0() == wethAddress ? uint256(reserve0) : uint256(reserve1);

        // Use 30% of pool's WETH reserve — enough to meaningfully crash price
        // while staying within realistic liquidity bounds on any network
        uint256 whaleSwapAmount = wethReserve * 30 / 100;
        require(whaleSwapAmount > 0, "Pool has no WETH liquidity");

        // Manipulate the Uniswap pool to decrease ETH price
        address whale = address(0x999);
        vm.deal(whale, whaleSwapAmount * 2);

        vm.startPrank(whale);

        // Get WETH for the whale
        (bool success,) = wethAddress.call{value: whaleSwapAmount}("");
        require(success, "WETH deposit failed");

        // Approve Uniswap router to spend whale's WETH
        IERC20(wethAddress).approve(uniswapV2Router02, whaleSwapAmount);

        // Build path for swap
        address[] memory path = new address[](2);
        path[0] = wethAddress;
        path[1] = usdcAddress;

        // Whale swaps a portion of pool liquidity for USDC, crashing ETH price
        router.swapExactTokensForTokens({
            amountIn: whaleSwapAmount, amountOutMin: 0, path: path, to: whale, deadline: block.timestamp + 15 minutes
        });

        vm.stopPrank();

        vm.startPrank(user);

        // Record balances before swap
        uint256 ethBalanceBefore = address(globalAllocation).balance;
        uint256 usdcBalanceBefore = token2.balanceOf(address(globalAllocation));

        // Trigger the swap by calling balanceFundsExternal
        // This will call swapTokenForEth since ETH price crashed (currentAllocation < desiredAllocation)
        globalAllocation.balanceFundsExternal();

        // Get balances after swap
        uint256 ethBalanceAfter = address(globalAllocation).balance;
        uint256 usdcBalanceAfter = token2.balanceOf(address(globalAllocation));

        // Verify USDC balance decreased
        assertLt(usdcBalanceAfter, usdcBalanceBefore, "USDC balance should decrease after swap");

        // Verify ETH balance increased
        assertGt(ethBalanceAfter, ethBalanceBefore, "ETH balance should increase after swap");

        vm.stopPrank();
    }
}
