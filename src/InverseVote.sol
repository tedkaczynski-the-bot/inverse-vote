// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

/**
 * @title InverseVote
 * @notice Wrapper that provides inverse voting power for any ERC20 token.
 * @dev Smaller holders get proportionally MORE voting power per token.
 *      Optional staking provides time-weighted bonus (anti-sybil).
 * 
 * Philosophy: Traditional DAOs are plutocracies — whales dominate.
 * InverseVote flips this. Your first tokens matter most.
 * 
 * Voting power = sqrt(balance) * timeMultiplier
 * - sqrt() compresses whale advantage dramatically
 * - Time multiplier rewards long-term commitment
 */
contract InverseVote {
    
    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════
    
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientStake();
    error TransferFailed();
    
    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════
    
    event Staked(address indexed user, uint256 amount, uint256 totalStaked);
    event Unstaked(address indexed user, uint256 amount, uint256 totalStaked);
    event TokenSet(address indexed token);
    
    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════
    
    /// @notice The underlying ERC20 token
    IERC20 public immutable token;
    
    /// @notice Staked balances
    mapping(address => uint256) public stakedBalance;
    
    /// @notice Timestamp when user first staked (for time bonus)
    mapping(address => uint256) public stakeStartTime;
    
    /// @notice Total staked across all users
    uint256 public totalStaked;
    
    /// @notice Minimum stake duration for max time bonus (default: 30 days)
    uint256 public constant MAX_BONUS_DURATION = 30 days;
    
    /// @notice Maximum time multiplier (2x at 30 days)
    uint256 public constant MAX_TIME_MULTIPLIER = 2e18; // 2.0 in 18 decimals
    
    /// @notice Base multiplier (1x)
    uint256 public constant BASE_MULTIPLIER = 1e18;
    
    /// @notice Precision for sqrt calculation
    uint256 private constant PRECISION = 1e18;
    
    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Create an InverseVote wrapper for any ERC20
     * @param _token The ERC20 token to wrap
     */
    constructor(address _token) {
        if (_token == address(0)) revert ZeroAddress();
        token = IERC20(_token);
        emit TokenSet(_token);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // STAKING
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Stake tokens to participate in inverse voting with time bonus
     * @param amount Amount of tokens to stake
     */
    function stake(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        
        // Transfer tokens to this contract
        bool success = token.transferFrom(msg.sender, address(this), amount);
        if (!success) revert TransferFailed();
        
        // If first stake, record start time
        if (stakedBalance[msg.sender] == 0) {
            stakeStartTime[msg.sender] = block.timestamp;
        }
        
        stakedBalance[msg.sender] += amount;
        totalStaked += amount;
        
        emit Staked(msg.sender, amount, stakedBalance[msg.sender]);
    }
    
    /**
     * @notice Unstake tokens (resets time bonus if full unstake)
     * @param amount Amount of tokens to unstake
     */
    function unstake(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (stakedBalance[msg.sender] < amount) revert InsufficientStake();
        
        stakedBalance[msg.sender] -= amount;
        totalStaked -= amount;
        
        // Reset time bonus if fully unstaked
        if (stakedBalance[msg.sender] == 0) {
            stakeStartTime[msg.sender] = 0;
        }
        
        // Transfer tokens back
        bool success = token.transfer(msg.sender, amount);
        if (!success) revert TransferFailed();
        
        emit Unstaked(msg.sender, amount, stakedBalance[msg.sender]);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // VOTING POWER
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Get voting power from wallet balance only (no staking required)
     * @param account The address to check
     * @return Voting power (sqrt of balance, 18 decimals)
     */
    function getVotingPowerFromBalance(address account) public view returns (uint256) {
        uint256 balance = token.balanceOf(account);
        return sqrt(balance * PRECISION);
    }
    
    /**
     * @notice Get voting power from staked balance with time bonus
     * @param account The address to check
     * @return Voting power (sqrt of staked * time multiplier, 18 decimals)
     */
    function getVotingPowerFromStake(address account) public view returns (uint256) {
        uint256 staked = stakedBalance[account];
        if (staked == 0) return 0;
        
        uint256 basePower = sqrt(staked * PRECISION);
        uint256 timeMultiplier = getTimeMultiplier(account);
        
        return (basePower * timeMultiplier) / PRECISION;
    }
    
    /**
     * @notice Get total voting power (balance + staked with bonus)
     * @param account The address to check
     * @return Total voting power
     */
    function getVotingPower(address account) external view returns (uint256) {
        return getVotingPowerFromBalance(account) + getVotingPowerFromStake(account);
    }
    
    /**
     * @notice Get the time multiplier for an account (1x to 2x over 30 days)
     * @param account The address to check
     * @return Time multiplier (18 decimals, 1e18 = 1x, 2e18 = 2x)
     */
    function getTimeMultiplier(address account) public view returns (uint256) {
        uint256 startTime = stakeStartTime[account];
        if (startTime == 0) return BASE_MULTIPLIER;
        
        uint256 elapsed = block.timestamp - startTime;
        if (elapsed >= MAX_BONUS_DURATION) {
            return MAX_TIME_MULTIPLIER;
        }
        
        // Linear interpolation from 1x to 2x
        uint256 bonus = (elapsed * PRECISION) / MAX_BONUS_DURATION;
        return BASE_MULTIPLIER + bonus;
    }
    
    /**
     * @notice Get stake duration for an account
     * @param account The address to check
     * @return Duration in seconds (0 if not staking)
     */
    function getStakeDuration(address account) external view returns (uint256) {
        uint256 startTime = stakeStartTime[account];
        if (startTime == 0) return 0;
        return block.timestamp - startTime;
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // COMPARISON HELPERS
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Compare voting power: show how inverse voting changes the game
     * @param whale Address of a large holder
     * @param minnow Address of a small holder
     * @return whaleBalance Whale's token balance
     * @return minnowBalance Minnow's token balance
     * @return whaleVotingPower Whale's voting power
     * @return minnowVotingPower Minnow's voting power
     * @return balanceRatio How many X more tokens whale has
     * @return powerRatio How many X more voting power whale has
     */
    function compareVoters(address whale, address minnow) external view returns (
        uint256 whaleBalance,
        uint256 minnowBalance,
        uint256 whaleVotingPower,
        uint256 minnowVotingPower,
        uint256 balanceRatio,
        uint256 powerRatio
    ) {
        whaleBalance = token.balanceOf(whale) + stakedBalance[whale];
        minnowBalance = token.balanceOf(minnow) + stakedBalance[minnow];
        whaleVotingPower = this.getVotingPower(whale);
        minnowVotingPower = this.getVotingPower(minnow);
        
        // Avoid division by zero
        if (minnowBalance > 0) {
            balanceRatio = (whaleBalance * PRECISION) / minnowBalance;
        }
        if (minnowVotingPower > 0) {
            powerRatio = (whaleVotingPower * PRECISION) / minnowVotingPower;
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // MATH
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Babylonian square root
     * @param x The number to take sqrt of
     * @return y The square root
     */
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
