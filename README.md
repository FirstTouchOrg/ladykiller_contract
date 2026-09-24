# Ladykiller — Smart Contract Audit Package

Ladykiller is an on-chain chase-and-guess game: each round a player bets on which "day" (1–49) a
pursuer catches the heroine, or simply on DAY / NIGHT. The result is derived from a single
Chainlink VRF v2.5 random word. Website: https://ladykiller.io

This repository contains **only** the code submitted for audit.

## Audit scope

| File | Lines | nSLOC | SHA-256 |
|---|---:|---:|---|
| `contracts/LadykillerGame.sol` | 786 | 658 | `6c39a4bff716580f0c8f5406d23c0475562885ebeab9b49a57a35181c9052241` |
| `contracts/FixedVRFConsumerBaseV2Plus.sol` | 33 | 23 | `c56ff1962dbba30972f598833f04021cad70342c5276f9cf3ffa5f4533cc438b` |
| **Total in scope** | **819** | **681** | |

`FixedVRFConsumerBaseV2Plus` is an abstract base inherited by `LadykillerGame`; they deploy as a
single contract.

**Flattened single file** (for reading only — same code, all imports inlined):
`flattened/LadykillerGame.flattened.sol` (1,870 lines). Of these, only the two in-scope sections
(`// File contracts/FixedVRFConsumerBaseV2Plus.sol` and `// File contracts/LadykillerGame.sol`)
are ours; everything else is unmodified OpenZeppelin / Chainlink library code.

## Out of scope

| Path | Why |
|---|---|
| `@openzeppelin/contracts` **5.4.0** (Ownable, Ownable2Step, Pausable, ReentrancyGuard, SafeERC20, IERC20) | Standard library, unmodified |
| `@chainlink/contracts` **1.5.0** (`VRFV2PlusClient`, `IVRFCoordinatorV2Plus`) | Standard library, unmodified |
| `contracts/test-only/*` (`LKRToken`, `SelectiveRefundToken`, VRF mock import) | Test fixtures only, never deployed to mainnet |
| `test/*` | Hardhat tests |

## Deployment under review

| | |
|---|---|
| Network | BNB Smart Chain **Testnet** (chainId 97) |
| Address | [`0xe2DFDBa1fD353D55c7F868D19A004eBb88100a3D`](https://testnet.bscscan.com/address/0xe2DFDBa1fD353D55c7F868D19A004eBb88100a3D) |
| Compiler | solc **0.8.24** (`0.8.24+commit.e11b9ed9`), optimizer on, runs 200, **viaIR: true**, EVM `paris` |
| Upgradeability | None (no proxy, no `delegatecall`, no `selfdestruct`) |

Building this repository reproduces the deployed runtime bytecode exactly (16,204 bytes, identical
including the metadata hash, with immutables masked).

The testnet deployment uses a test token as the wager token.

## Mainnet deployment parameters

The audited code is token-agnostic: the wager token and all VRF settings are constructor
arguments, so the mainnet contract is this exact code deployed with the values below. No code
change is made between audit and mainnet deployment.

Constructor order: `wagerTokenAddress, vrfCoordinator, keyHash, subscriptionId, callbackGasLimit,
requestConfirmations, timeout, nativePayment, initialSafetyBuffer, initialKeeper`

| Parameter | Mainnet (BNB Smart Chain, chainId 56) | Testnet deployment (reference) |
|---|---|---|
| `wagerTokenAddress` | **USDT** `0x55d398326f99059fF775485246999027B3197955` (18 decimals → `minimumBet` = 1 USDT) | Test token, 18 decimals |
| `vrfCoordinator` | `0xd691f04bc0C9a24Edb78af9E005Cf85768F694C9` (Chainlink VRF v2.5, official) | `0xDA3b641D438362C440Ac5458c57e00a712b66700` |
| `keyHash` | One of the official BSC mainnet lanes — 200 gwei `0x130dba50ad435d4ecc214aad0d5820474137bd68e7e77724144f27c3c377d3d4`, 500 gwei `0xeb0f72532fed5c94b4caf7b49caf454b35a729608a441101b9269efb7efe2c6c`, 1000 gwei `0xb94a4fdb12830e15846df59b27d7c5d92c9c24c10cf6ae49655681ba560848dd`; lane TBD at deployment | 50 gwei lane |
| `subscriptionId` | New mainnet subscription, TBD at deployment | — |
| `callbackGasLimit` | TBD at deployment (Chainlink max 2,500,000) | 500,000 |
| `requestConfirmations` | TBD at deployment (Chainlink range 3–200) | 3 |
| `timeout` (`vrfTimeout`) | TBD at deployment | 3,600 s |
| `nativePayment` | TBD at deployment | `true` (BNB) |
| `initialSafetyBuffer` | TBD at deployment | 0 |
| `initialKeeper` | TBD at deployment (contract enforces ≠ deployer, ≠ zero address) | — |

Fixed in code regardless of parameters: betting window 45 s, final VRF deadline 24 h
(`VRF_FINAL_TIMEOUT`), ≤50 claims/refunds per transaction.

## Roles

| Role | Can do |
|---|---|
| **Owner** (`Ownable2Step`; renounce disabled) | `pause` / `unpause`, `setKeeper`, `setSafetyBuffer`, `withdrawFreeFunds` (only funds not reserved for active rounds or owed to players). Also passes `onlyKeeper`. Accepting a new owner invalidates all existing keeper grants (`keeperEpoch`). |
| **Keeper** (set in constructor, must not be the deployer) | `startRound` only |
| **Chainlink VRF coordinator** (immutable) | `rawFulfillRandomWords` |
| **Anyone** | `placeBets`, `closeRound`, `closeEmptyRound`, `finalizeRound`, `claim` / `claimMany`, `cancelUnrequestedRound`, `releaseStalledRound`, `cancelTimedOutRound`, `refundBatch`, `claimDeferredRefund`, `fundBankroll` |

## Round lifecycle

```
startRound ─► BETTING (45 s) ─┬─ no bets ──► closeEmptyRound ──► SKIPPED
                              ├─ closeRound (within vrfTimeout of deadline) ─► WAITING_RANDOMNESS
                              └─ not closed within vrfTimeout ──► cancelUnrequestedRound ─► CANCELLED

WAITING_RANDOMNESS ─┬─ VRF fulfilled within 24 h ─► RANDOM_READY ─► finalizeRound ─► SETTLED ─► claim
                    ├─ after vrfTimeout: releaseStalledRound (frees the active slot, request stays live)
                    └─ no VRF after 24 h (VRF_FINAL_TIMEOUT) ─► cancelTimedOutRound ─► CANCELLED

CANCELLED ─► refundBatch (≤50 players/tx, fixed cursor) ─► failed transfers ─► claimDeferredRefund
```

## Key invariant

Token balance of the contract ≥ `lockedPlayerPayouts` + `totalActiveReserve` + `safetyBuffer`.
Every bet is rejected if, after it, the worst-case payout of the active round would break this.

## Known and accepted risks (please confirm, not re-report)

1. **VRF delay → refund.** If the VRF request is still unanswered 24 h after it was made, the round
   is cancelled and all bets are refunded; a late fulfillment is ignored. A VRF operator withholding
   a response for 24 h could therefore turn a losing round into a refund. Accepted by design.
2. **Owner trust.** Owner can pause betting, change the safety buffer (no upper bound) and manage
   keepers, but cannot withdraw reserved or owed funds, cannot change the VRF coordinator and cannot
   set the result.
3. **Immutable coordinator.** A Chainlink coordinator migration requires deploying a new contract.
4. **Token assumptions.** Standard ERC-20 only; fee-on-transfer is detected and rejected; rebasing
   tokens are unsupported. If a player cannot receive tokens (e.g. blocklisted), `refundBatch`
   defers that refund instead of reverting.

## Build and test

```bash
pnpm install --frozen-lockfile
pnpm compile
pnpm test        # 16 tests
pnpm flatten     # regenerates flattened/LadykillerGame.flattened.sol
```
