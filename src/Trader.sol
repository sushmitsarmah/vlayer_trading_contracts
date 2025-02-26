// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IPoolManager } from "v4-core/interfaces/IPoolManager.sol";
// import "v4-core/interfaces/IHookFeeManager.sol";
// import "v4-periphery/base/PeripheryPayments.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title TradingBot
 * @dev A trading bot that manages budgets for different coins and executes trades on Uniswap V4
 */
contract TradingBot is Ownable, ReentrancyGuard {
    IPoolManager public immutable poolManager;
    
    // Mapping from user address to token address to budget amount
    mapping(address => mapping(address => uint256)) public budgets;
    
    // Mapping from user address to token address to amount spent
    mapping(address => mapping(address => uint256)) public spent;
    
    // Mapping from user address to token address to profit amount
    mapping(address => mapping(address => uint256)) public profits;
    
    // Events
    event BudgetSet(address indexed user, address indexed token, uint256 amount);
    event TradeExecuted(address indexed user, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event ProfitRecorded(address indexed user, address indexed token, uint256 amount);
    
    constructor(IPoolManager _poolManager) Ownable(msg.sender) {
        poolManager = _poolManager;
    }
    
    /**
     * @dev Sets budget for a specific coin
     * @param token The address of the token
     * @param amount The budget amount
     */
    function setBudget(address token, uint256 amount) external payable {
        if (token == address(0)) {
            // ETH case - budget is directly added from msg.value
            require(msg.value == amount, "Amount doesn't match sent ETH");
            budgets[msg.sender][token] += amount;
        } else {
            // ERC20 case - transfer tokens to contract
            IERC20(token).transferFrom(msg.sender, address(this), amount);
            budgets[msg.sender][token] += amount;
        }
        
        emit BudgetSet(msg.sender, token, budgets[msg.sender][token]);
    }
    
    /**
     * @dev Executes a buy trade (swap)
     * @param tokenIn Token to spend
     * @param tokenOut Token to receive
     * @param amountIn Amount of tokenIn to spend
     * @param amountOutMinimum Minimum amount of tokenOut to receive
     * @param poolKey The pool key for the swap
     * @param hookData Additional data for hooks
     * @return amountOut The amount of tokenOut received
     */
    function executeBuy(
        address tokenIn, 
        address tokenOut, 
        uint256 amountIn, 
        uint256 amountOutMinimum,
        PoolKey calldata poolKey,
        bytes calldata hookData
    ) external nonReentrant returns (uint256 amountOut) {
        // Check if the user has enough budget
        require(budgets[msg.sender][tokenIn] >= amountIn, "Insufficient budget");
        
        // Update the budget
        budgets[msg.sender][tokenIn] -= amountIn;
        spent[msg.sender][tokenIn] += amountIn;
        
        // Prepare swap parameters
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: _isToken0(tokenIn, tokenOut, poolKey.currency0, poolKey.currency1),
            amountSpecified: int256(amountIn),
            sqrtPriceLimitX96: _isToken0(tokenIn, tokenOut, poolKey.currency0, poolKey.currency1) ? 
                TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1
        });
        
        BalanceDelta delta;
        
        // Execute the swap
        if (tokenIn == address(0)) {
            // ETH case
            delta = poolManager.swap{value: amountIn}(poolKey, params, hookData);
        } else {
            // ERC20 case
            // Approve the pool manager to use tokenIn
            IERC20(tokenIn).approve(address(poolManager), amountIn);
            delta = poolManager.swap(poolKey, params, hookData);
        }
        
        // Calculate the output amount
        amountOut = _isToken0(tokenIn, tokenOut, poolKey.currency0, poolKey.currency1) ? 
            uint256(-delta.amount1()) : 
            uint256(-delta.amount0());
            
        require(amountOut >= amountOutMinimum, "Insufficient output amount");
        
        // Emit event
        emit TradeExecuted(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
        
        return amountOut;
    }
    
    /**
     * @dev Executes a sell trade (swap)
     * @param tokenIn Token to spend (previously bought)
     * @param tokenOut Token to receive (original token used to buy)
     * @param amountIn Amount of tokenIn to spend
     * @param amountOutMinimum Minimum amount of tokenOut to receive
     * @param poolKey The pool key for the swap
     * @param hookData Additional data for hooks
     * @return profit The profit made from this trade
     */
    function executeSell(
        address tokenIn, 
        address tokenOut, 
        uint256 amountIn, 
        uint256 amountOutMinimum,
        PoolKey calldata poolKey,
        bytes calldata hookData
    ) external nonReentrant returns (uint256 profit) {
        // Prepare swap parameters
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: _isToken0(tokenIn, tokenOut, poolKey.currency0, poolKey.currency1),
            amountSpecified: int256(amountIn),
            sqrtPriceLimitX96: _isToken0(tokenIn, tokenOut, poolKey.currency0, poolKey.currency1) ? 
                TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1
        });
        
        BalanceDelta delta;
        
        // Execute the swap
        if (tokenIn == address(0)) {
            // ETH case
            delta = poolManager.swap{value: amountIn}(poolKey, params, hookData);
        } else {
            // ERC20 case
            // Approve the pool manager to use tokenIn
            IERC20(tokenIn).approve(address(poolManager), amountIn);
            delta = poolManager.swap(poolKey, params, hookData);
        }
        
        // Calculate the output amount
        uint256 amountOut = _isToken0(tokenIn, tokenOut, poolKey.currency0, poolKey.currency1) ? 
            uint256(-delta.amount1()) : 
            uint256(-delta.amount0());
            
        require(amountOut >= amountOutMinimum, "Insufficient output amount");
        
        // Calculate profit (if any)
        uint256 currentSpent = spent[msg.sender][tokenOut];
        
        if (amountOut > currentSpent) {
            profit = amountOut - currentSpent;
            profits[msg.sender][tokenOut] += profit;
            
            // Reset spent
            spent[msg.sender][tokenOut] = 0;
            
            // Add remaining amount to budget
            budgets[msg.sender][tokenOut] += amountOut;
        } else {
            // Update spent
            spent[msg.sender][tokenOut] -= amountOut;
            
            // Add amount back to budget
            budgets[msg.sender][tokenOut] += amountOut;
        }
        
        // Emit events
        emit TradeExecuted(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
        if (profit > 0) {
            emit ProfitRecorded(msg.sender, tokenOut, profit);
        }
        
        return profit;
    }
    
    /**
     * @dev Withdraws budget for a specific coin
     * @param token The address of the token
     * @param amount The amount to withdraw
     */
    function withdrawBudget(address token, uint256 amount) external nonReentrant {
        require(budgets[msg.sender][token] >= amount, "Insufficient budget");
        
        // Update budget
        budgets[msg.sender][token] -= amount;
        
        // Transfer tokens to user
        if (token == address(0)) {
            // ETH case
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            // ERC20 case
            IERC20(token).transfer(msg.sender, amount);
        }
    }
    
    /**
     * @dev Checks if tokenA is token0 in the pool
     */
    function _isToken0(
        address tokenA, 
        address tokenB, 
        Currency currency0, 
        Currency currency1
    ) internal pure returns (bool) {
        return (tokenA == Currency.unwrap(currency0) && tokenB == Currency.unwrap(currency1));
    }
    
    /**
     * @dev Gets the budget for a specific coin
     * @param user The user address
     * @param token The token address
     * @return The budget amount
     */
    function getBudget(address user, address token) external view returns (uint256) {
        return budgets[user][token];
    }
    
    /**
     * @dev Gets the profit for a specific coin
     * @param user The user address
     * @param token The token address
     * @return The profit amount
     */
    function getProfit(address user, address token) external view returns (uint256) {
        return profits[user][token];
    }
    
    /**
     * @dev Gets the amount spent for a specific coin
     * @param user The user address
     * @param token The token address
     * @return The spent amount
     */
    function getSpent(address user, address token) external view returns (uint256) {
        return spent[user][token];
    }
    
    // Fallback to receive ETH
    receive() external payable {}
}