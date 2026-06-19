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

    /// Same scenario as master. The deposit now settles the accumulator first, so the late
    /// depositor is credited from zero and Alice keeps the rewards she actually earned.
    function test_accountingDrift_isFixed() public {
        vm.prank(alice);
        pool.deposit(100 ether);

        vm.warp(block.timestamp + 100);

        vm.prank(attacker);
        pool.deposit(100 ether);

        vm.prank(attacker);
        pool.harvest();

        vm.prank(alice);
        pool.harvest();

        uint256 attackerReward = reward.balanceOf(attacker);
        uint256 aliceReward = reward.balanceOf(alice);

        console2.log("rewards accrued while only Alice staked (wei):", uint256(100 ether));
        console2.log("attacker harvested (wei):", attackerReward);
        console2.log("alice harvested   (wei):", aliceReward);

        assertEq(attackerReward, 0, "attacker earns nothing from before joining");
        assertApproxEqAbs(aliceReward, 100 ether, 1e6, "alice keeps the full accrued amount");
    }
}
