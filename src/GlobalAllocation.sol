// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
// import {console2} from "forge-std/console2.sol";

contract GlobalAllocation is Ownable, ReentrancyGuard {
    /* Errors */
    error Allocation__DesiredAllocationOutsideOfRange();
    error Allocation__RebalancePercentageOutsideOfRange();
    error Allocation__OverflowUpdatingCurrentAllocation();
    error Allocation__ReAllocationNotNeeded();
    error Allocation__ReceiveEthValueIsNull();
    error Allocation__ReceiveToken2ValueIsNull();
    error Allocation__Token2DepositFailed();
    error Allocation__EthWithdrawFailed();
    error Allocation__TokenWithdrawFailed();

    /* State Variables */
    uint24 public sDesiredAllocationPercentage; // desired allocation percentage for ( ETH(in USD) / ETH(in USD) * USDC ) * 1000000
    uint24 public sCurrentAllocationPercentage;
    uint24 public sRebalanceThreshold; // threshold between current and desired allocation for rebalancing
    uint24 public sUpdateAllocationThreshold; // threshold for adjusting desired allocation percentages
    uint24 public sSlippagePercentage;
    address public immutable I_TOKEN1; // token1 address (WETH)
    address public immutable I_TOKEN2; // token2 address
    IUniswapV2Router02 public immutable I_UNISWAP_V2_ROUTER_02;
    uint256 private sEthPrice; // Only set when this minus current eth price is outside of sUpdateAllocationThreshold

    /* Events */
    event SwappedEthForToken(uint256 maxEthOut, uint256 minTokenIn);
    event SwappedTokenForEth(uint256 maxTokenOut, uint256 minEthIn);
    event RebalancePerformed(uint256 totalPortfolioValueInToken2, uint24 currentEthAllocationPercentage);
    event BalanceFundsCalled(address caller);
    event EthDeposited(uint256 ethAmount);
    event Token2Deposited(address token2Address, uint256 token2Amount);
    event EthAndToken2Withdrawn(uint256 ethAmount, uint256 token2amount);

    constructor(
        address _token1,
        address _token2,
        address _uniswapRouter,
        uint24 _desiredAllocationPercentage,
        uint24 _rebalanceThreshold,
        uint24 _slippagePercentage
    ) Ownable(msg.sender) {
        I_TOKEN1 = _token1;
        I_TOKEN2 = _token2;
        I_UNISWAP_V2_ROUTER_02 = IUniswapV2Router02(_uniswapRouter);
        setDesiredAllocationPercentage(_desiredAllocationPercentage);
        setRebalanceThreshold(_rebalanceThreshold);

        sSlippagePercentage = _slippagePercentage;
    }

    /**
     * @dev sets desired allocation percentage
     * @param _sDesiredAllocationPercentage 1.0000%-100.0000%
     */
    function setDesiredAllocationPercentage(uint24 _sDesiredAllocationPercentage) public {
        if (_sDesiredAllocationPercentage <= 1e4 || _sDesiredAllocationPercentage >= 1e6) {
            revert Allocation__DesiredAllocationOutsideOfRange();
        }

        sDesiredAllocationPercentage = _sDesiredAllocationPercentage;
    }

    function setRebalanceThreshold(uint24 _rebalanceThreshold) public {
        if (_rebalanceThreshold <= 1e3 || _rebalanceThreshold >= 1e5) {
            revert Allocation__RebalancePercentageOutsideOfRange();
        }

        sRebalanceThreshold = _rebalanceThreshold;
    }

    /**
     * @dev Updates the current allocation percentage based on Uniswap quoted Eth price
     * If immediatley after deposit use ChainLink Pricefeed to get ETH value in token2 terms
     * The Chainlink value is to ensure that the Uniswap price quote is reasonable when performing a larger transaction
     * Use a Uniswap quote to get ETH value in token2 terms
     * Add Eth Price to a state variable if outside of threshold
     */
    function quoteEthPriceInToken2() private returns (uint256 ethPriceInToken2) {
        address[] memory token1ToToken2Path = new address[](2);
        token1ToToken2Path[0] = I_TOKEN1;
        token1ToToken2Path[1] = I_TOKEN2;

        uint256[] memory returnAmounts = I_UNISWAP_V2_ROUTER_02.getAmountsOut(1 ether, token1ToToken2Path);
        ethPriceInToken2 = returnAmounts[1];

        // gets shotty setting eth price using ethPrice in Token 2 because could have a price outsdie of threshold
        // Does not re-balance as tight. While not the vision is potentially more profitable
        uint256 priceDiff = ethPriceInToken2 > sEthPrice ? ethPriceInToken2 - sEthPrice : sEthPrice - ethPriceInToken2;
        if (priceDiff * 1e6 / ethPriceInToken2 > sUpdateAllocationThreshold) {
            sEthPrice = ethPriceInToken2;
        }
    }

    /**
     * @dev Update Portfolio based on most recently quoted token2 value
     */
    function updateCurrentAllocationPercentage(uint256 ethPriceInToken2)
        private
        returns (uint256 totalPortfolioValueInToken2)
    {
        uint256 ethPortfolioBalanceInToken2 = ethPriceInToken2 * address(this).balance / 1e18;
        totalPortfolioValueInToken2 = ethPortfolioBalanceInToken2 + IERC20Metadata(I_TOKEN2).balanceOf(address(this));

        if (address(this).balance == 0) {
            sCurrentAllocationPercentage = 0;
            return totalPortfolioValueInToken2;
        } else {
            if (ethPortfolioBalanceInToken2 * 1e6 / totalPortfolioValueInToken2 > type(uint24).max) {
                revert Allocation__OverflowUpdatingCurrentAllocation();
            }
            // casting to 'uint24' is safe because revert-error statement above ensures value ≤ type(uint24).max
            sCurrentAllocationPercentage =
            // forge-lint: disable-next-line(unsafe-typecast)
            uint24(ethPortfolioBalanceInToken2 * 1e6 / totalPortfolioValueInToken2);
            // console2.log("Current Eth Allocation Percentage:", sCurrentAllocationPercentage);
            // console2.log("Desired Eth Allocation Percentage:", sDesiredAllocationPercentage);
            if (
                (sCurrentAllocationPercentage > sDesiredAllocationPercentage
                            ? sCurrentAllocationPercentage - sDesiredAllocationPercentage
                            : sDesiredAllocationPercentage - sCurrentAllocationPercentage) < sRebalanceThreshold
            ) {
                revert Allocation__ReAllocationNotNeeded();
            }
        }

        emit RebalancePerformed(totalPortfolioValueInToken2, sCurrentAllocationPercentage / 10000);
        // console2.log("Contract Eth balance", address(this).balance);
        // console2.log("Eth balance in token2", ethPortfolioBalanceInToken2);
        // console2.log("Contract token2 balance", IERC20Metadata(I_TOKEN2).balanceOf(address(this)));
        // console2.log("Total portfolio balnce in token2", totalPortfolioValueInToken2); // 6 decimals
        // console2.log("Eth To Token2 allocation percentage", sCurrentAllocationPercentage); // 4 decimals
    }

    /**
     * @dev Allow owner to balance funds manually
     */
    function balanceFundsExternal() external {
        emit BalanceFundsCalled(msg.sender);
        balanceFunds();
    }

    /**
     * @dev Balances funds based on desired allocation percentage
     */
    function balanceFunds() internal {
        // Get the most recent Eth quote
        uint256 _ethPriceInToken2 = quoteEthPriceInToken2();

        // Update the current allocation percentage
        uint256 _totalPortfolioValueInToken2 = updateCurrentAllocationPercentage({ethPriceInToken2: _ethPriceInToken2});

        // Logic for balancing funds
        if (sCurrentAllocationPercentage < sDesiredAllocationPercentage) {
            swapTokenForEth({
                ethPriceInToken2: _ethPriceInToken2, totalPortfolioValueInToken2: _totalPortfolioValueInToken2
            });
        } else if (sCurrentAllocationPercentage > sDesiredAllocationPercentage) {
            swapEthForToken({
                ethPriceInToken2: _ethPriceInToken2, totalPortfolioValueInToken2: _totalPortfolioValueInToken2
            });
        } else {
            return;
        }
    }

    /**
     * @dev Swaps ETH for token address using Uniswap
     */
    function swapEthForToken(uint256 ethPriceInToken2, uint256 totalPortfolioValueInToken2) internal {
        uint256 minTokenToRecieve = (sCurrentAllocationPercentage - sDesiredAllocationPercentage)
            * totalPortfolioValueInToken2 / (10 ** IERC20Metadata(I_TOKEN2).decimals());

        // Use quoted price to send set a max eth willing to pay for transaction to go through
        uint256 maxEthToSend = (minTokenToRecieve * 1e18) / ethPriceInToken2;

        // console2.log("Total Portfolio Value in Token2", totalPortfolioValueInToken2);
        // console2.log("Current allocation percentage", sCurrentAllocationPercentage);
        // console2.log("Desired allocation percentage", sDesiredAllocationPercentage);
        // console2.log("Max Eth to send", maxEthToSend);
        // console2.log("Min token to receive", minTokenToRecieve);

        address[] memory token1ToToken2Path = new address[](2);
        token1ToToken2Path[0] = I_TOKEN1;
        token1ToToken2Path[1] = I_TOKEN2;

        uint256[] memory returnAmounts = I_UNISWAP_V2_ROUTER_02.swapExactETHForTokens{value: maxEthToSend}({
            amountOutMin: minTokenToRecieve,
            path: token1ToToken2Path,
            to: address(this),
            deadline: block.timestamp + 15 minutes
        });

        emit SwappedEthForToken(returnAmounts[0], returnAmounts[1]);
    }

    /**
     * @dev Swaps token for ETH using Uniswap
     */
    function swapTokenForEth(uint256 ethPriceInToken2, uint256 totalPortfolioValueInToken2) internal {
        uint256 maxTokenToSend = (sDesiredAllocationPercentage - sCurrentAllocationPercentage)
            * totalPortfolioValueInToken2 / (10 ** IERC20Metadata(I_TOKEN2).decimals());

        // Use quoted price to set a min eth received for transaction to go through
        uint256 minEthToRecieve = (maxTokenToSend * 1e18 * (1e6 - sSlippagePercentage)) / (1e6 * ethPriceInToken2);

        // console2.log("Total Portfolio Value in Token2", totalPortfolioValueInToken2);
        // console2.log("Current allocation percentage", sCurrentAllocationPercentage);
        // console2.log("Desired allocation percentage", sDesiredAllocationPercentage);
        // console2.log("Max token to send", maxTokenToSend);
        // console2.log("Min Eth to receive", minEthToRecieve);

        // Approve Uniswap router to spend USDC
        IERC20Metadata(I_TOKEN2).approve(address(I_UNISWAP_V2_ROUTER_02), maxTokenToSend);

        address[] memory token2ToToken1Path = new address[](2);
        token2ToToken1Path[0] = I_TOKEN2;
        token2ToToken1Path[1] = I_TOKEN1;

        uint256[] memory returnAmounts = I_UNISWAP_V2_ROUTER_02.swapExactTokensForETH({
            amountIn: maxTokenToSend,
            amountOutMin: minEthToRecieve,
            path: token2ToToken1Path,
            to: address(this),
            deadline: block.timestamp + 15 minutes
        });

        emit SwappedTokenForEth(returnAmounts[0], returnAmounts[1]);
    }

    /**
     * @dev Accept ETH deposits
     */
    receive() external payable {
        if (msg.value <= 0) {
            revert Allocation__ReceiveEthValueIsNull();
        }

        emit EthDeposited(msg.value);
    }

    /**
     * @dev Accept token2 deposits
     * @param _amount Amount of token2 to transfer from user's wallet to this contract
     * @return success Boolean indicating if the transfer was successful
     */
    function depositToken2(uint256 _amount) external returns (bool success) {
        if (_amount <= 0) {
            revert Allocation__ReceiveToken2ValueIsNull();
        }

        // Transfer token2 from msg.sender to this contract
        success = IERC20Metadata(I_TOKEN2).transferFrom(msg.sender, address(this), _amount);
        if (!success) {
            revert Allocation__Token2DepositFailed();
        }

        emit Token2Deposited(I_TOKEN2, _amount);
    }

    /**
     * @dev Allow user to withdraw all funds from the contract
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 ethToWithdraw = address(this).balance;
        uint256 token2ToWithdraw = IERC20Metadata(I_TOKEN2).balanceOf(address(this));

        (bool success,) = msg.sender.call{value: ethToWithdraw}("");
        if (!success) {
            revert Allocation__EthWithdrawFailed();
        }

        success = IERC20Metadata(I_TOKEN2).transfer(msg.sender, token2ToWithdraw);
        if (!success) {
            revert Allocation__TokenWithdrawFailed();
        }

        emit EthAndToken2Withdrawn(ethToWithdraw, token2ToWithdraw);
    }
}
