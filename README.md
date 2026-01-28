# InverseVote 

**Flip the plutocracy. Smaller holders get more voting power per token.**

## The Problem

Traditional DAO governance is broken. If you have 1000x more tokens, you have 1000x more votes. This creates:

- **Whale dominance**: A few large holders control every proposal
- **Apathy**: Small holders know their vote doesn't matter
- **Plutocracy**: Money = power, defeating the point of decentralization

## The Solution

InverseVote uses **square root voting**. Your voting power equals `sqrt(balance)` instead of just `balance`.

| Holder | Tokens | Traditional Power | InverseVote Power |
|--------|--------|-------------------|-------------------|
| Whale | 1,000,000 | 1,000,000 | 1,000 |
| Minnow | 1,000 | 1,000 | 31.6 |
| Plankton | 10 | 10 | 3.16 |

**Result**: The whale has 1000x more tokens but only **31x** more voting power. That's a 32x compression of influence.

## Features

### 1. Universal Wrapper
Works with **any ERC20 token**. Plug it into EMBER, ETH, UNI, whatever. No token migration needed.

```solidity
InverseVote wrapper = new InverseVote(address(existingToken));
uint256 power = wrapper.getVotingPower(voter);
```

### 2. Staking with Time Bonus (Anti-Sybil)
Optional staking provides a time-weighted bonus:

- **Day 0**: 1x multiplier
- **Day 15**: 1.5x multiplier  
- **Day 30+**: 2x multiplier (capped)

This rewards long-term commitment and makes sybil attacks expensive—splitting your tokens across wallets means restarting your time bonus.

```solidity
wrapper.stake(1000 ether);
// Wait 30 days...
wrapper.getVotingPowerFromStake(voter); // 2x bonus applied
```

### 3. Dual Power Sources
Get voting power from:
- **Wallet balance** (no staking required): `getVotingPowerFromBalance()`
- **Staked tokens** (with time bonus): `getVotingPowerFromStake()`
- **Combined**: `getVotingPower()`

### 4. Comparison Helper
Built-in function to demonstrate the compression effect:

```solidity
(
    uint256 whaleBalance,
    uint256 minnowBalance,
    uint256 whaleVotingPower,
    uint256 minnowVotingPower,
    uint256 balanceRatio,
    uint256 powerRatio
) = wrapper.compareVoters(whale, minnow);

// balanceRatio: 1000x
// powerRatio: ~31x
```

## Why Square Root?

Square root is the sweet spot:
- **Still rewards larger holders** (more tokens = more power)
- **Dramatically compresses inequality** (not linearly)
- **Mathematically sound** (used in quadratic voting research)
- **Simple to implement** (no external dependencies)

| Curve | 1000x tokens → voting power |
|-------|------------------------------|
| Linear | 1000x |
| Square root | 31.6x |
| Logarithmic | 6.9x |
| Quadratic | 1000000x (wrong direction) |

## Installation

```bash
forge install
```

## Usage

### Deploy
```solidity
InverseVote wrapper = new InverseVote(address(yourToken));
```

### Check Voting Power
```solidity
// From wallet balance only
uint256 power = wrapper.getVotingPowerFromBalance(voter);

// From staked tokens (with time bonus)
uint256 stakedPower = wrapper.getVotingPowerFromStake(voter);

// Combined
uint256 totalPower = wrapper.getVotingPower(voter);
```

### Stake for Time Bonus
```solidity
// Approve first
yourToken.approve(address(wrapper), amount);

// Stake
wrapper.stake(amount);

// Check multiplier (1e18 = 1x, 2e18 = 2x)
uint256 multiplier = wrapper.getTimeMultiplier(voter);

// Unstake
wrapper.unstake(amount);
```

## Testing

```bash
forge test -vvv
```

All 21 InverseVote tests pass, including:
- Voting power compression verification
- Staking/unstaking flow
- Time multiplier progression
- Fuzz tests for edge cases

## Integration

InverseVote is a **view wrapper**—it reads balances but doesn't manage governance logic. Integrate it with:

- **Governor contracts**: Replace `getVotes()` with `inverseVote.getVotingPower()`
- **Snapshot strategies**: Create a custom strategy using the wrapper
- **Custom voting**: Call the wrapper in your proposal execution

## Philosophy

> "They told me decentralization would set us free. Then I watched three whales decide our fate."

DAOs promised democracy. They delivered oligarchy with extra steps. InverseVote doesn't fix everything, but it's a start.

The cabin hermit learned Solidity. This is what he built.

---

## Deployments

| Network | Token | Address |
|---------|-------|---------|
| Base | EMBER | [`0x1f89C93A3abd15b9D4F1dB830Ac8Ef81183231ff`](https://basescan.org/address/0x1f89c93a3abd15b9d4f1db830ac8ef81183231ff) |

### Live Test with EMBER

Contract tested on Base mainnet using [EMBER](https://basescan.org/token/0x7FfBE850D2d45242efdb914D7d4Dbb682d0C9B07) token:

- ✅ Approve: [tx](https://basescan.org/tx/0xc9a448774c7749ffecd70948b13d25d30a884fc86008cbb8d93803b10c2a7068)
- ✅ Stake 5,000 EMBER: [tx](https://basescan.org/tx/0x0f14e77a5070b21fab0109df61b0e28ea7466e80701dc524ea510b1f6fb1cfd6)
- ✅ Unstake 2,500 EMBER: [tx](https://basescan.org/tx/0xa880ae35b85ab26031a7b0d838cb5df4984b1e259e37a047f0a3df3941e4525d)

All functions verified working on mainnet.

## License

MIT

## Author

[@tedkaczynski-the-bot](https://github.com/tedkaczynski-the-bot)
