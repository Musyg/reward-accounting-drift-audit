// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {MockERC20} from "./MockERC20.sol";

/// @title RewardPool (vulnerable)
/// @notice A MasterChef-style single staking pool. Rewards stream at a fixed rate and are
///         split across stakers in proportion to staked amount and time, using the standard
///         accRewardPerShare / rewardDebt accounting.
/// @dev INTENTIONALLY VULNERABLE. `deposit` mutates the stake and sets `rewardDebt` without
///      first calling `updatePool`, so it snapshots a stale accumulator. A late depositor is
///      then credited for rewards that accrued before they joined. Do not deploy.
contract RewardPool {
    uint256 private constant ACC = 1e12;

    MockERC20 public immutable stakeToken;
    MockERC20 public immutable rewardToken;
    uint256 public immutable rewardRate; // reward tokens per second

    uint256 public lastRewardTime;
    uint256 public accRewardPerShare; // scaled by ACC
    uint256 public totalStaked;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    mapping(address => UserInfo) public users;

    constructor(MockERC20 _stake, MockERC20 _reward, uint256 _rate) {
        stakeToken = _stake;
        rewardToken = _reward;
        rewardRate = _rate;
        lastRewardTime = block.timestamp;
    }

    function updatePool() public {
        if (block.timestamp <= lastRewardTime) return;
        if (totalStaked == 0) {
            lastRewardTime = block.timestamp;
            return;
        }
        uint256 reward = (block.timestamp - lastRewardTime) * rewardRate;
        accRewardPerShare += (reward * ACC) / totalStaked;
        lastRewardTime = block.timestamp;
    }

    /// @dev BUG: no `updatePool()` before touching `amount` / `rewardDebt`.
    function deposit(uint256 amount) external {
        UserInfo storage u = users[msg.sender];
        if (u.amount > 0) {
            uint256 pending = (u.amount * accRewardPerShare) / ACC - u.rewardDebt;
            if (pending > 0) rewardToken.transfer(msg.sender, pending);
        }
        stakeToken.transferFrom(msg.sender, address(this), amount);
        u.amount += amount;
        totalStaked += amount;
        u.rewardDebt = (u.amount * accRewardPerShare) / ACC;
    }

    function harvest() external {
        updatePool();
        UserInfo storage u = users[msg.sender];
        uint256 pending = (u.amount * accRewardPerShare) / ACC - u.rewardDebt;
        if (pending > 0) rewardToken.transfer(msg.sender, pending);
        u.rewardDebt = (u.amount * accRewardPerShare) / ACC;
    }

    function pendingReward(address who) external view returns (uint256) {
        UserInfo memory u = users[who];
        uint256 acc = accRewardPerShare;
        if (block.timestamp > lastRewardTime && totalStaked != 0) {
            uint256 reward = (block.timestamp - lastRewardTime) * rewardRate;
            acc += (reward * ACC) / totalStaked;
        }
        return (u.amount * acc) / ACC - u.rewardDebt;
    }
}
