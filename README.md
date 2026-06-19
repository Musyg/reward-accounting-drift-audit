# Reward Accounting Drift, Demonstration Security Review

A self-contained demonstration of a smart-contract security review: a deliberately
vulnerable MasterChef-style staking pool whose `deposit` snapshots a stale reward
accumulator, the reward theft it allows (proven with a passing
[Foundry](https://book.getfoundry.sh) proof-of-concept), and a `fixed` branch where the
same scenario is neutralised.

> This is a demonstration on intentionally vulnerable code. `RewardPool` was written to
> showcase audit methodology end to end. It is not production code, not a real client
> engagement, and must never be deployed. The finding is a real vulnerability in this demo
> contract, not an invented severity.

## Why this repo exists

Anyone can write "I audit smart contracts" in a bio. This repo shows the work instead: a
target, a concrete finding, an executable proof, and a verified fix. If it isn't
reproducible, it isn't done.

## Repository layout

The review lives across two branches:

| Branch | Contents | What a green `forge test` means |
|--------|----------|---------------------------------|
| `master` | The vulnerable pool and the PoC that exploits it | a late depositor harvests rewards earned before they joined |
| `fixed`  | The remediated pool and the same scenario | the late depositor earns nothing from before joining |

- `src/RewardPool.sol`, the contract under review
- `test/RewardPool.poc.t.sol`, the proof-of-concept
- `Reward_Accounting_Drift_Review.pdf`, the full written report

## Finding

| ID | Severity | Summary |
|----|----------|---------|
| H-01 | High | Stale accumulator on deposit. `deposit` updates the user's stake and `rewardDebt` without first calling `updatePool`, so it snapshots an out-of-date `accRewardPerShare`. A depositor who joins right before the accumulator is refreshed is credited for rewards that accrued while they held no stake, draining them from the stakers who earned them. |

PoC numbers on `master`: Alice is the sole staker for 100 seconds, so all 100 reward
tokens of that window are hers. The attacker deposits at the end and harvests immediately:
the attacker walks away with 50 tokens and Alice receives only 50. On `fixed` the attacker
receives 0 and Alice keeps the full 100.

## Reproduce it

Requires [Foundry](https://book.getfoundry.sh/getting-started/installation).

```bash
git clone https://github.com/Musyg/reward-accounting-drift-audit.git
cd reward-accounting-drift-audit
forge install

# master: the reward theft succeeds
forge test -vv

# fixed: the same attack is neutralised
git checkout fixed
forge test -vv
```

## The fix

Call `updatePool()` at the start of `deposit`, before the stake and `rewardDebt` are
touched. Settling the accumulator first means a new depositor's `rewardDebt` is snapshotted
against the up-to-date `accRewardPerShare`, so they are credited only from the block they
join. This is the invariant every MasterChef-derived pool relies on: refresh the
accumulator before any change to a stake.

## How severity is rated

High: direct theft of accrued rewards from honest stakers by an unprivileged actor. The
only precondition is depositing while rewards are pending accrual, which is the normal
state of an active pool.
