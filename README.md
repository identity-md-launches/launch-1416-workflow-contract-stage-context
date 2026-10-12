# PULSE — Keep the Swarm Alive

Implemented contracts for the PULSE project launch: a plain fixed-supply ERC-20
and one permanent, fully onchain Drone NFT per wallet. Heartbeats keep a Drone
alive; deposited PULSE determines its Hive rank. Staking earns no yield.

This contribution includes contracts, vendored dependencies, tests, ABI exports
and integration documentation. The separate manifest contributor owns
`launch.json`; independent review, publication, attestation, admission, deployment
and the frontend follow this source stage.

## Build and verify

```sh
forge build
forge test
forge fmt --check
python3 scripts/export_abis.py --check
```

`foundry.toml` pins Solidity **0.8.26**, Cancun, optimizer with 200 runs, IR
compilation, and `bytecode_hash = "none"`. Foundry and the pinned compiler must be
available; all Solidity dependencies are vendored as ordinary files. No FFI,
filesystem cheatcode permissions, RPC, wallet key, environment-variable test
configuration or network access is required. Dependency provenance and licenses
are in [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md).

Regenerate ABI exports after source changes with:

```sh
forge build
python3 scripts/export_abis.py
```

## Deployment parameters

Deploy in this order:

| Solidity contract | Source | Nonpayable constructor arguments | Role |
| --- | --- | --- | --- |
| `LaunchToken` | `src/LaunchToken.sol` | None | Launch token |
| `PulseDrone` | `src/PulseDrone.sol` | `address pulseToken_ = $token` | Application contract |

`LaunchToken` is named **Pulse**, symbol **PULSE**, with 18 decimals and exactly
**1,000,000,000 PULSE (10^27 minor units)** minted once to its deployer, the launch
factory. It has no mint, burn, owner, tax, pause, blocklist or upgrade function.

`PulseDrone` binds `$token` immutably at construction. The launch explicitly
supports this dependency reference, so the workflow's alternative one-time
owner binding path is unnecessary: **there is no `owner()` or
`setPulseToken(address)` function and no admin panel to display**. No privileged
constructor argument is needed. Neither the factory nor its caller receives
administrative control.

Constructors make no external calls and do not require any other contract's code
to be present. The token argument must be a nonzero address other than the Drone
itself. Staking checks for token code on first use and reverts with
`PulseTokenNotDeployed()` if it is absent. There is no unset-token launch mode;
the manifest must provide the real `$token` reference.

Only these two contracts are deployed. `DroneArt` is an internal-only library,
fully inlined into `PulseDrone`, with no link placeholders or renderer address.
The factory supplies its own distributor, pool and initialization guard.

The supplied launch terms are Ethereum (chain ID **1**), pairing with IMD at
`0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, pool fee **12500 (1.25%)**,
tick spacing **60**, and manifest initial price
`"79228162514264337593543950336"`. The service derives the effective opening price
from the policy's **2,500 IMD** opening market cap and deployed token ordering.
The factory allocates **10% to the swarm distributor, 88% to liquidity and 2% to
the payer (or policy treasury when applicable)**. Neither application code nor
the Drone constructor receives a launch allocation or implements trading fees.
The supplied launch owner is `0x0f94ac347c64c1ebf4dc84e6b657ac629268e2a6`;
these contracts require no owner argument or privileged role for that address.
These terms are handoff context for the manifest and services, not application
constructor inputs. Services own policy and signed-artifact linkage.

## Drone behavior and explicit assumptions

- **Mint:** `mint()` costs no PULSE or ETH (the transaction still costs gas).
  IDs are sequential from 1 to 4,096. A wallet can mint once for itself, forever.
  Contracts can mint if they implement `IERC721Receiver`. Transfers, both safe
  transfer overloads, all approvals, and approval revocation revert with
  `Soulbound()`. There is no burn, remint or recovery path.
- **First heartbeat:** Minting starts Alive, with `streak = bestStreak =
  totalBeats = 1` and `lastBeatAt = block.timestamp`. It emits `Minted`, `Beat`
  and the standard ERC-721 `Transfer` event. The next beat is available 20 hours
  later.
- **Timing:** Only the owner can beat their own Drone. Elapsed times below 20
  hours revert. A beat from exactly 20 through exactly 48 hours increments the
  streak; any later beat resets it to 1. A Drone is Alive through exactly 48
  hours and Dormant from the next second. Every successful beat increments
  `totalBeats`; `bestStreak` never decreases. Expiry alone changes the derived
  status without a transaction, event, or storage update. Stored streak remains
  visible until the next beat. Best streak and lifetime beats survive dormancy.
- **Traits:** The permanent seed is
  `keccak256(abi.encode(tokenId, minter, block.prevrandao))`. `seed % 100` gives
  Worker (0–39), Scout (40–69), Guard (70–89), Builder (90–99). These are
  probability weights, not guaranteed collection quotas. Color is
  `(seed >> 8) % 8`, eyes `(seed >> 16) % 6`. These cosmetic traits can be
  influenced by validators and by minting/reverting through multiple wallets;
  they provide no rewards, custody privileges or rank advantage. This is not
  verifiable randomness or proof of a unique human.
- **Staking:** Approve PULSE to `PulseDrone`, then call `stake(amount)` in
  18-decimal minor units. Zero amounts revert. Only credited deposits affect
  rank. `unstake(amount)` returns exactly the caller's credited PULSE instantly,
  also when Dormant. Staking and unstaking never count as a beat. There are no
  rewards, fees, lock periods, liquidation, or forfeiture.
- **Art:** Base64 JSON embeds a base64 512×512 SVG. Alive art uses the permanent
  palette, amber glow and a four-second opacity pulse; Dormant art is entirely
  greyscale with no animation. Both show the fixed eyes and Caste emblem. Aura
  tiers mean **7, 30 and 100 consecutive heartbeat counts**, matching `streak`,
  not elapsed 24-hour calendar days (beats are permitted every 20 hours). Rings
  follow stored streak, stay grey during dormancy, and disappear on a reset to
  1. Worker and higher ranks have a corner badge. The `Staked` metadata value is
  an exact decimal PULSE string; fractional values retain 18 places.

| Staked PULSE | Hive rank |
| --- | --- |
| Less than 1,000 | Larva |
| At least 1,000 | Worker |
| At least 100,000 | Guard |
| At least 1,000,000 | Royal Guard |
| At least 10,000,000 | Queen's Guard |

See the [decoded onchain art samples](docs/previews/README.md) for Alive and
Dormant SVGs generated by the contract in a local fixture.

## Integration

Use [docs/ABI.md](docs/ABI.md) and the generated ABI arrays in
[docs/abi/LaunchToken.json](docs/abi/LaunchToken.json) and
[docs/abi/PulseDrone.json](docs/abi/PulseDrone.json).

`droneOf(wallet)` returns zero before mint. `stateOf(tokenId)` returns all stats
and derived traits in one struct. `getDrones(start, count)` uses **one-based
token IDs**, allows up to 256 results, truncates at the last ID, and returns an
empty array beyond it. Start zero and count above 256 revert, even for an empty
collection. Count zero returns an empty array for a valid start.

Read pages against one block tag for a coherent Hive snapshot. Compute total
Alive and the longest active streak on the site; neither is stored globally.
Use Alive-only entries for the active streak leaderboard. Read block timestamps
for cooldown and dormancy countdowns; a browser clock is only an estimate.
Status and metadata can change without events as time passes, so refresh at
boundaries and on new blocks as well as after `Beat`, `Staked` and `Unstaked`.
The ABI exposes no configurable token-binding admin flow.

## After launch

There are **no owner settings, subscriptions, oracle addresses or initialization
calls**. The services must deploy the accepted bytecode with the correct `$token`
argument, publish/verify source, and provide the actual deployed addresses and
exact pool key to the frontend. Admission and signed-artifact linkage are service
responsibilities. An independent contributor must review accepted source and
the completed manifest before release, especially constructor linkage and the
custody behavior. Local tests do not replace that review.

Users are responsible for retaining control of their minting wallet and sending
heartbeats. The dApp should explain the permanent wallet binding before minting,
request exact deposit approvals, show transaction confirmation and cooldown
state, and enable withdrawals regardless of Alive status.

Direct ERC-20 transfers to the Drone bypass the staking ledger and are
**uncredited and unrecoverable**. Accidental tokens and forced ETH cannot be
rescued. Ordinary ETH sends and ETH attached to contract calls revert. There is
no admin withdrawal, pause, migration or upgrade power, so a lost wallet cannot
be recovered and an implementation fault cannot be repaired in place. Only the
fixed, standard `LaunchToken` is supported; rebasing or malicious substitute
tokens are outside the custody model. Incorrect `$token` linkage is irreversible
and must be caught in manifest review.

## Verification coverage

The [local verification record](docs/VERIFICATION.md) records the passing build,
42-test suite, formatting, ABI checks, and reproducible offline verification.

The Foundry suite covers fixed supply and plain transfers; mint uniqueness and
the full 4,096 cap; every soulbound mutation; receiver rejection and reentrancy;
20/48-hour boundaries and fuzzed timing; batched reads; staking conservation,
allowance/balance failures, token reverts/false/optional returns, fee deductions,
reentrancy, all rank thresholds, and instant withdrawals after dormancy; decoded
metadata and SVG features; and factory-style deployment, runtime size and the
launch's forbidden-opcode scan.

Stateful invariant testing mixes deposits, withdrawals, donations, heartbeats
and prohibited transfers across four users. It checks ownership, fixed traits,
every heartbeat statistic, balances and aggregate liabilities after each step,
then withdraws all credited deposits at the end. Defaults are 512 fuzz cases per
fuzz test and 128 invariant runs of 64 steps each.

Solidity reports an unreachable receiver check in OpenZeppelin's inherited
safe-transfer implementation because the soulbound transfer override always
reverts; safe mint's receiver check is tested and still executes. Foundry lint
also identifies the deliberate cosmetic `prevrandao` seed, time comparisons,
bounded index casts, and the deliberate exact deposit-balance check. These uses
are documented and covered by tests. Slither and Mythril are not installed and
were not run. The required independent launch review remains separate.
