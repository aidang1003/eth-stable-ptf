// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {UD60x18, ud} from "@prb-math/UD60x18.sol";
// import {console2} from "forge-std/console2.sol";

contract GlobalAllocation is Ownable, ReentrancyGuard {
    /* Errors */
    error Allocation__Uint24DesiredAllocationOutsideOfRange();
    error Allocation__Uint256DesiredAllocationOutsideOfRange();
    error Allocation__OverflowUpdatingDesiredAllocation();
    error Allocation__Uint24CurrentAllocationOutsideOfRange();
    error Allocation__Uint256CurrentAllocationOutsideOfRange();
    error Allocation__OverflowUpdatingCurrentAllocation();

    error Allocation__RebalancePercentageOutsideOfRange();
    error Allocation__ReAllocationNotNeeded();
    error Allocation__ReceiveEthValueIsNull();
    error Allocation__ReceiveToken2ValueIsNull();
    error Allocation__Token2DepositFailed();
    error Allocation__EthWithdrawFailed();
    error Allocation__TokenWithdrawFailed();

    /* State Variables */
    uint24 public sDesiredAllocationPercentage; // desired allocation percentage for ( ETH(in USD) / ETH(in USD) * USDC ) * 1000000
    uint24 public sCurrentAllocationPercentage;
    uint256 public sEthPrice; // Only set when this minus current eth price is outside of sUpdateAllocationThreshold
    uint256 public sEthPriceMax; // At this Eth price or below hold 100% ETH
    uint256 public sEthPriceMin; // At this Eth price or above hold 100% of a stable token
    uint24 public sRebalanceThreshold; // threshold between current and desired allocation for rebalancing
    uint24 public sUpdateAllocationThreshold; // threshold for adjusting desired allocation percentages
    uint24 public sSlippagePercentage;
    UD60x18 public immutable I_FACTOR; // Shape the curve to buy/sell ETH on
    address public immutable I_TOKEN1; // token1 address (WETH)
    address public immutable I_TOKEN2; // token2 address
    IUniswapV2Router02 public immutable I_UNISWAP_V2_ROUTER_02;

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
        uint24 _desiredAllocationPercentage, // take out after implementing alt method
        uint24 _rebalanceThreshold,
        uint24 _slippagePercentage,
        uint256 _ethPriceMin,
        uint256 _ethPriceMax,
        uint256 _factor
    ) Ownable(msg.sender) {
        I_TOKEN1 = _token1;
        I_TOKEN2 = _token2;
        I_UNISWAP_V2_ROUTER_02 = IUniswapV2Router02(_uniswapRouter);
        sEthPriceMin = _ethPriceMin;
        sEthPriceMax = _ethPriceMax;
        I_FACTOR = ud(_factor);
        setDesiredAllocationPercentage(_desiredAllocationPercentage);
        setRebalanceThreshold(_rebalanceThreshold);

        sSlippagePercentage = _slippagePercentage;
    }

    /**
     * @dev sets desired allocation percentage
     * @param _desiredAllocationPercentage uint256 0.0000%-100.0000%
     */
    function setDesiredAllocationPercentageUint256(uint256 _desiredAllocationPercentage) public {
        if (_desiredAllocationPercentage > type(uint24).max) {
            revert Allocation__OverflowUpdatingDesiredAllocation();
        }
        // casting to 'uint24' is safe because revert-error statement above ensures value ≤ type(uint24).max
        // forge-lint: disable-next-line(unsafe-typecast)
        setDesiredAllocationPercentage(uint24(_desiredAllocationPercentage));
    }

    function setDesiredAllocationPercentage(uint24 _desiredAllocationPercentage) public {
        if (_desiredAllocationPercentage < 0 || _desiredAllocationPercentage > 1e6) {
            revert Allocation__Uint24DesiredAllocationOutsideOfRange();
        }

        sDesiredAllocationPercentage = _desiredAllocationPercentage;
    }

    /**
     * @dev sets current allocation percentage
     * @param _currentAllocationPercentage uint256 0.0000%-100.0000%
     */
    function setCurrentAllocationPercentageUint256(uint256 _currentAllocationPercentage) public {
        if (_currentAllocationPercentage > type(uint24).max) {
            revert Allocation__OverflowUpdatingCurrentAllocation();
        }
        // casting to 'uint24' is safe because revert-error statement above ensures value ≤ type(uint24).max
        // forge-lint: disable-next-line(unsafe-typecast)
        setCurrentAllocationPercentage(uint24(_currentAllocationPercentage));
    }

    function setCurrentAllocationPercentage(uint24 _currentAllocationPercentage) public {
        if (_currentAllocationPercentage < 0 || _currentAllocationPercentage > 1e6) {
            revert Allocation__Uint24CurrentAllocationOutsideOfRange();
        }
        sCurrentAllocationPercentage = _currentAllocationPercentage;
    }

    function setRebalanceThreshold(uint24 _rebalanceThreshold) public {
        if (_rebalanceThreshold <= 1e3 || _rebalanceThreshold >= 1e5) {
            revert Allocation__RebalancePercentageOutsideOfRange();
        }

        sRebalanceThreshold = _rebalanceThreshold;
    }

    /**
     * @dev Use a Uniswap quote to get ETH value in token2 terms
     * Only read from chain state
     */
    function quoteEthPriceInToken2() public view returns (uint256 ethPriceInToken2) {
        address[] memory token1ToToken2Path = new address[](2);
        token1ToToken2Path[0] = I_TOKEN1;
        token1ToToken2Path[1] = I_TOKEN2;

        uint256[] memory returnAmounts = I_UNISWAP_V2_ROUTER_02.getAmountsOut(1 ether, token1ToToken2Path);
        ethPriceInToken2 = returnAmounts[1];
    }

    /**
     * @dev Check if the change in Eth price is greater than the threshold for updating allocation percentages
     * designed to be called off-chain before balancing funds
     * @param ethPriceInToken2
     */
    function updateEthPrice(uint256 ethPriceInToken2) public view returns (bool update) {
        uint256 priceDiff = ethPriceInToken2 > sEthPrice ? ethPriceInToken2 - sEthPrice : sEthPrice - ethPriceInToken2;
        if (priceDiff * 1e6 / ethPriceInToken2 > sUpdateAllocationThreshold) {
            update = true;
        } else {
            update = false;
        }
    }

    /**
     *
     * @param ethPriceInToken2 Only update sEthPRice if we're doing a re-balance
     */
    function setEthPriceInToken2(uint256 ethPriceInToken2) public {
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
        returns (uint256 totalPortfolioValueInToken2, uint256 currentAllocationPercentage)
    {
        uint256 ethPortfolioBalanceInToken2 = ethPriceInToken2 * address(this).balance / 1e18;
        totalPortfolioValueInToken2 = ethPortfolioBalanceInToken2 + IERC20Metadata(I_TOKEN2).balanceOf(address(this));

        if (address(this).balance == 0) {
            currentAllocationPercentage = 0;
        } else if (IERC20Metadata(I_TOKEN2).balanceOf(address(this)) == 0) {
            currentAllocationPercentage = 1000000;
        } else {
            currentAllocationPercentage = ethPortfolioBalanceInToken2 * 1e6 / totalPortfolioValueInToken2;

            // console2.log("Current Eth Allocation Percentage:", currentAllocationPercentage);
            // console2.log("Desired Eth Allocation Percentage:", sDesiredAllocationPercentage);
        }

        if (
            (currentAllocationPercentage > sDesiredAllocationPercentage
                        ? currentAllocationPercentage - sDesiredAllocationPercentage
                        : sDesiredAllocationPercentage - currentAllocationPercentage) < sRebalanceThreshold
        ) {
            revert Allocation__ReAllocationNotNeeded();
        }
        setCurrentAllocationPercentageUint256(currentAllocationPercentage);

        emit RebalancePerformed(totalPortfolioValueInToken2, sCurrentAllocationPercentage / 10000);
        // console2.log("Contract Eth balance", address(this).balance);
        // console2.log("Eth balance in token2", ethPortfolioBalanceInToken2);
        // console2.log("Contract token2 balance", IERC20Metadata(I_TOKEN2).balanceOf(address(this)));
        // console2.log("Total portfolio balnce in token2", totalPortfolioValueInToken2); // 6 decimals
        // console2.log("Eth To Token2 allocation percentage", sCurrentAllocationPercentage); // 4 decimals
    }

    /**
     * @dev Update desired allocation percentage based on formula
     * @param _ethPriceinToken2 Need the most recent eth quote
     */
    function updateDesiredAllocationPercentage(uint256 _ethPriceinToken2)
        public
        view
        returns (uint256 desiredAllocation)
    {
        if (_ethPriceinToken2 < sEthPriceMin) {
            desiredAllocation = 1e6; //100%
        } else if (_ethPriceinToken2 > sEthPriceMax) {
            desiredAllocation = 0; //0%
        } else {
            UD60x18 priceRatio = ud(((_ethPriceinToken2 - sEthPriceMin) * 1e18) / (sEthPriceMax - sEthPriceMin));
            UD60x18 powered = priceRatio.pow(I_FACTOR);

            uint256 poweredUnwrap = powered.unwrap();
            uint256 powered4Decimals = poweredUnwrap / 1e12; // truncate down to percent format
            desiredAllocation = 1e6 - powered4Decimals;
        }

        // console2.log("Eth Price", _ethPriceinToken2);
        // console2.log("Price Ratio", priceRatio.unwrap());
        // console2.log("Exponent", I_FACTOR.unwrap());
        // console2.log("Powered Unwrap", poweredUnwrap);
        // console2.log("Powered after truncating decimals", powered4Decimals);
        // console2.log("Desired Allocation", desiredAllocation);
    }

    /**
     * @dev Balances funds based on desired and current allocation percentages
     */
    function balanceFunds() public {
        emit BalanceFundsCalled(msg.sender);

        // Get the most recent Eth quote
        uint256 ethPriceInToken2 = quoteEthPriceInToken2();

        uint256 desiredAllocation = updateDesiredAllocationPercentage(ethPriceInToken2);
        // console2.log("Balance funds desired allocation", desiredAllocation);
        setDesiredAllocationPercentageUint256(desiredAllocation);

        // Update the current allocation percentage
        (uint256 totalPortfolioValueInToken2,) = updateCurrentAllocationPercentage(ethPriceInToken2);

        // Logic for balancing funds
        if (sCurrentAllocationPercentage < sDesiredAllocationPercentage) {
            swapTokenForEth({
                ethPriceInToken2: ethPriceInToken2, totalPortfolioValueInToken2: totalPortfolioValueInToken2
            });
        } else if (sCurrentAllocationPercentage > sDesiredAllocationPercentage) {
            swapEthForToken({
                ethPriceInToken2: ethPriceInToken2, totalPortfolioValueInToken2: totalPortfolioValueInToken2
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
