// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {InverseVote} from "../src/InverseVote.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract InverseVoteTest is Test {
    InverseVote public inverseVote;
    MockERC20 public token;
    
    address public whale = makeAddr("whale");
    address public minnow = makeAddr("minnow");
    address public plankton = makeAddr("plankton");
    
    uint256 public constant WHALE_BALANCE = 1_000_000 ether;   // 1M tokens
    uint256 public constant MINNOW_BALANCE = 1_000 ether;      // 1K tokens
    uint256 public constant PLANKTON_BALANCE = 10 ether;       // 10 tokens
    
    function setUp() public {
        token = new MockERC20("Test Token", "TEST");
        inverseVote = new InverseVote(address(token));
        
        // Distribute tokens
        token.mint(whale, WHALE_BALANCE);
        token.mint(minnow, MINNOW_BALANCE);
        token.mint(plankton, PLANKTON_BALANCE);
        
        // Approve staking
        vm.prank(whale);
        token.approve(address(inverseVote), type(uint256).max);
        
        vm.prank(minnow);
        token.approve(address(inverseVote), type(uint256).max);
        
        vm.prank(plankton);
        token.approve(address(inverseVote), type(uint256).max);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_constructor_setsToken() public view {
        assertEq(address(inverseVote.token()), address(token));
    }
    
    function test_constructor_revertsOnZeroAddress() public {
        vm.expectRevert(InverseVote.ZeroAddress.selector);
        new InverseVote(address(0));
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // INVERSE VOTING POWER TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_votingPower_sqrtCompression() public view {
        // Whale has 1000x more tokens than minnow
        // But should have only ~31.6x more voting power (sqrt(1000) ≈ 31.6)
        
        uint256 whalePower = inverseVote.getVotingPowerFromBalance(whale);
        uint256 minnowPower = inverseVote.getVotingPowerFromBalance(minnow);
        
        // Both should have non-zero power
        assertGt(whalePower, 0, "Whale should have voting power");
        assertGt(minnowPower, 0, "Minnow should have voting power");
        
        // Whale has more power, but ratio is compressed
        uint256 balanceRatio = WHALE_BALANCE / MINNOW_BALANCE; // 1000x
        uint256 powerRatio = whalePower / minnowPower;
        
        // Power ratio should be approximately sqrt(1000) ≈ 31-32
        assertLt(powerRatio, 35, "Power ratio should be sqrt-compressed");
        assertGt(powerRatio, 30, "Power ratio should be around 31.6");
        
        console2.log("Balance ratio:", balanceRatio, "x");
        console2.log("Power ratio:", powerRatio, "x");
        console2.log("Compression factor:", balanceRatio / powerRatio, "x");
    }
    
    function test_votingPower_smallHoldersMatterMore() public view {
        // Calculate "power per token" for each tier
        uint256 whalePower = inverseVote.getVotingPowerFromBalance(whale);
        uint256 minnowPower = inverseVote.getVotingPowerFromBalance(minnow);
        uint256 planktonPower = inverseVote.getVotingPowerFromBalance(plankton);
        
        // Power per token (normalized)
        uint256 whalePPT = (whalePower * 1e18) / WHALE_BALANCE;
        uint256 minnowPPT = (minnowPower * 1e18) / MINNOW_BALANCE;
        uint256 planktonPPT = (planktonPower * 1e18) / PLANKTON_BALANCE;
        
        // Smaller holders should have MORE power per token
        assertGt(planktonPPT, minnowPPT, "Plankton should have more power per token than minnow");
        assertGt(minnowPPT, whalePPT, "Minnow should have more power per token than whale");
        
        console2.log("Whale power per token:", whalePPT);
        console2.log("Minnow power per token:", minnowPPT);
        console2.log("Plankton power per token:", planktonPPT);
    }
    
    function test_votingPower_zeroBalanceReturnsZero() public view {
        address nobody = address(0xdead);
        assertEq(inverseVote.getVotingPowerFromBalance(nobody), 0);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // STAKING TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_stake_updatesBalance() public {
        uint256 stakeAmount = 100 ether;
        
        vm.prank(minnow);
        inverseVote.stake(stakeAmount);
        
        assertEq(inverseVote.stakedBalance(minnow), stakeAmount);
        assertEq(inverseVote.totalStaked(), stakeAmount);
        assertEq(token.balanceOf(minnow), MINNOW_BALANCE - stakeAmount);
    }
    
    function test_stake_setsStartTime() public {
        vm.prank(minnow);
        inverseVote.stake(100 ether);
        
        assertEq(inverseVote.stakeStartTime(minnow), block.timestamp);
    }
    
    function test_stake_additionalStakeKeepsOriginalTime() public {
        vm.startPrank(minnow);
        
        inverseVote.stake(50 ether);
        uint256 firstStakeTime = block.timestamp;
        
        // Warp forward
        vm.warp(block.timestamp + 7 days);
        
        // Stake more
        inverseVote.stake(50 ether);
        
        vm.stopPrank();
        
        // Start time should still be original
        assertEq(inverseVote.stakeStartTime(minnow), firstStakeTime);
    }
    
    function test_stake_revertsOnZeroAmount() public {
        vm.prank(minnow);
        vm.expectRevert(InverseVote.ZeroAmount.selector);
        inverseVote.stake(0);
    }
    
    function test_unstake_returnsTokens() public {
        vm.startPrank(minnow);
        inverseVote.stake(100 ether);
        
        uint256 balanceBefore = token.balanceOf(minnow);
        inverseVote.unstake(50 ether);
        
        vm.stopPrank();
        
        assertEq(token.balanceOf(minnow), balanceBefore + 50 ether);
        assertEq(inverseVote.stakedBalance(minnow), 50 ether);
    }
    
    function test_unstake_fullUnstakeResetsTime() public {
        vm.startPrank(minnow);
        inverseVote.stake(100 ether);
        
        vm.warp(block.timestamp + 15 days);
        
        inverseVote.unstake(100 ether);
        vm.stopPrank();
        
        assertEq(inverseVote.stakeStartTime(minnow), 0);
    }
    
    function test_unstake_revertsOnInsufficientStake() public {
        vm.prank(minnow);
        vm.expectRevert(InverseVote.InsufficientStake.selector);
        inverseVote.unstake(100 ether);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TIME MULTIPLIER TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_timeMultiplier_startsAtOne() public {
        vm.prank(minnow);
        inverseVote.stake(100 ether);
        
        uint256 multiplier = inverseVote.getTimeMultiplier(minnow);
        assertEq(multiplier, 1e18, "Initial multiplier should be 1x");
    }
    
    function test_timeMultiplier_increasesOverTime() public {
        vm.prank(minnow);
        inverseVote.stake(100 ether);
        
        // After 15 days (half the max duration)
        vm.warp(block.timestamp + 15 days);
        
        uint256 multiplier = inverseVote.getTimeMultiplier(minnow);
        
        // Should be approximately 1.5x
        assertGt(multiplier, 1.4e18);
        assertLt(multiplier, 1.6e18);
    }
    
    function test_timeMultiplier_capsAtTwo() public {
        vm.prank(minnow);
        inverseVote.stake(100 ether);
        
        // After 30 days (max duration)
        vm.warp(block.timestamp + 30 days);
        uint256 multiplier30 = inverseVote.getTimeMultiplier(minnow);
        assertEq(multiplier30, 2e18, "Multiplier at 30 days should be 2x");
        
        // After 60 days (still capped)
        vm.warp(block.timestamp + 30 days);
        uint256 multiplier60 = inverseVote.getTimeMultiplier(minnow);
        assertEq(multiplier60, 2e18, "Multiplier should stay capped at 2x");
    }
    
    function test_timeMultiplier_appliedToVotingPower() public {
        vm.prank(minnow);
        inverseVote.stake(100 ether);
        
        uint256 initialPower = inverseVote.getVotingPowerFromStake(minnow);
        
        // Warp to max bonus
        vm.warp(block.timestamp + 30 days);
        
        uint256 maxPower = inverseVote.getVotingPowerFromStake(minnow);
        
        // Power should have doubled
        assertApproxEqRel(maxPower, initialPower * 2, 0.01e18);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // COMBINED VOTING POWER TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_getVotingPower_combinesBalanceAndStake() public {
        vm.prank(minnow);
        inverseVote.stake(500 ether); // Stake half
        
        uint256 balancePower = inverseVote.getVotingPowerFromBalance(minnow);
        uint256 stakePower = inverseVote.getVotingPowerFromStake(minnow);
        uint256 totalPower = inverseVote.getVotingPower(minnow);
        
        assertEq(totalPower, balancePower + stakePower);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // COMPARISON HELPER TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_compareVoters_showsCompression() public view {
        (
            uint256 whaleBalance,
            uint256 minnowBalance,
            uint256 whaleVotingPower,
            uint256 minnowVotingPower,
            uint256 balanceRatio,
            uint256 powerRatio
        ) = inverseVote.compareVoters(whale, minnow);
        
        assertEq(whaleBalance, WHALE_BALANCE);
        assertEq(minnowBalance, MINNOW_BALANCE);
        
        // Balance ratio is 1000x (1000e18 in 18 decimals)
        assertApproxEqRel(balanceRatio, 1000e18, 0.01e18);
        
        // Power ratio should be sqrt(1000) ≈ 31.6x
        assertGt(powerRatio, 30e18);
        assertLt(powerRatio, 35e18);
        
        console2.log("=== Whale vs Minnow ===");
        console2.log("Whale balance:", whaleBalance / 1e18, "tokens");
        console2.log("Minnow balance:", minnowBalance / 1e18, "tokens");
        console2.log("Balance ratio:", balanceRatio / 1e18, "x");
        console2.log("Whale voting power:", whaleVotingPower / 1e18);
        console2.log("Minnow voting power:", minnowVotingPower / 1e18);
        console2.log("Power ratio:", powerRatio / 1e18, "x");
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function testFuzz_sqrt_neverOverflows(uint256 x) public {
        // Should never revert
        inverseVote.getVotingPowerFromBalance(whale); // Just checking it doesn't panic
        
        // For direct sqrt testing, mint to a test address
        x = bound(x, 0, type(uint128).max);
        address testAddr = address(uint160(x + 1));
        token.mint(testAddr, x);
        uint256 result = inverseVote.getVotingPowerFromBalance(testAddr);
        assertLe(result, type(uint256).max);
    }
    
    function testFuzz_stakeUnstake_preservesTokens(uint256 amount) public {
        amount = bound(amount, 1, MINNOW_BALANCE);
        
        uint256 totalBefore = token.balanceOf(minnow);
        
        vm.startPrank(minnow);
        inverseVote.stake(amount);
        inverseVote.unstake(amount);
        vm.stopPrank();
        
        uint256 totalAfter = token.balanceOf(minnow);
        assertEq(totalAfter, totalBefore, "Tokens should be preserved");
    }
    
    function testFuzz_timeMultiplier_alwaysInRange(uint256 timeElapsed) public {
        timeElapsed = bound(timeElapsed, 0, 365 days);
        
        vm.prank(minnow);
        inverseVote.stake(100 ether);
        
        vm.warp(block.timestamp + timeElapsed);
        
        uint256 multiplier = inverseVote.getTimeMultiplier(minnow);
        
        assertGe(multiplier, 1e18, "Multiplier should be >= 1x");
        assertLe(multiplier, 2e18, "Multiplier should be <= 2x");
    }
}
