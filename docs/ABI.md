# Contract API

The ABI JSON files in `docs/abi/` are generated directly from the Solidity 0.8.26
build. Run `python3 scripts/export_abis.py --check` after `forge build` to verify
they match. Integer amounts use **PULSE minor units (10^18 per PULSE)** unless
explicitly described as display strings.

## LaunchToken

Constructor: `constructor()` (nonpayable). Mints `10^27` minor units to the
deployer. Standard ERC-20 `name`, `symbol`, `decimals`, `totalSupply`, `balanceOf`,
`allowance`, `approve`, `transfer`, `transferFrom`; standard `Transfer` and
`Approval` events and OpenZeppelin IERC-6093 errors. No permit or privileged
operations. An allowance of `type(uint256).max` follows standard OpenZeppelin
infinite-allowance semantics; the frontend should request exact amounts.

## PulseDrone

Constructor: `constructor(address pulseToken_)` (nonpayable), with manifest
argument **`$token`**. `pulseToken()` returns this immutable address. There is no
owner or setter.

| Function | Behavior / return |
| --- | --- |
| `mint() -> uint256 tokenId` | Mint the caller's permanent Drone and first heartbeat |
| `beat()` | Record a heartbeat for the caller's Drone |
| `stake(uint256 amount)` | Pull approved PULSE from the caller and credit their Drone |
| `unstake(uint256 amount)` | Return the caller's credited PULSE |
| `droneOf(address wallet) -> uint256` | Token ID, or zero if unminted |
| `stateOf(uint256 tokenId) -> DroneState` | Current snapshot; reverts for an unminted ID |
| `getDrones(uint256 start, uint256 count) -> DroneState[]` | Consecutive IDs starting at `start >= 1`; `count <= 256`; truncates at last mint |
| `totalMinted() -> uint256` | Total minted; IDs are contiguous and cannot burn |
| `totalStaked() -> uint256` | Sum of credited deposits; excludes direct donations |
| `rankOf(uint256 amount) -> Rank` | Pure rank lookup by minor units |
| `tokenURI(uint256 tokenId) -> string` | `data:application/json;base64,...` with embedded `data:image/svg+xml;base64,...` |
| `MAX_SUPPLY()` | 4096 |
| `BEAT_COOLDOWN()` | 72000 seconds |
| `ALIVE_WINDOW()` | 172800 seconds |
| `MAX_BATCH_SIZE()` | 256 |

ERC-721 read interfaces: `name()` = `Pulse Drone`, `symbol()` = `DRONE`,
`ownerOf`, `balanceOf`, `getApproved`, `isApprovedForAll`, `supportsInterface`.
ERC-165, ERC-721 and ERC-721 metadata interface IDs are supported; enumerable,
ERC-5192 and ERC-4906 extensions are not advertised. All approvals and transfers
revert; valid minted tokens always have no approved operator. Both
`safeTransferFrom` overloads revert.

### DroneState tuple, in ABI field order

| Field | Solidity type | Meaning |
| --- | --- | --- |
| `tokenId` | `uint256` | ID in 1..4096 |
| `owner` | `address` | Permanent minting wallet |
| `seed` | `bytes32` | Permanent cosmetic seed |
| `caste` | enum (`uint8`) | 0 Worker, 1 Scout, 2 Guard, 3 Builder |
| `color` | `uint8` | Palette index 0..7 |
| `eyes` | `uint8` | Eye index 0..5 |
| `alive` | `bool` | `now - lastBeatAt <= 172800` |
| `streak` | `uint256` | Stored current heartbeat streak; reset occurs on a late beat |
| `bestStreak` | `uint256` | Lifetime maximum streak |
| `totalBeats` | `uint256` | All successful heartbeats, including mint |
| `lastBeatAt` | `uint256` | Unix timestamp in seconds |
| `staked` | `uint256` | Credited PULSE minor units |
| `rank` | enum (`uint8`) | 0 Larva, 1 Worker, 2 Guard, 3 Royal Guard, 4 Queen's Guard |

Palette indices: 0 Amber `#D97706`, 1 Gold `#CA8A04`, 2 Copper `#B87333`,
3 Coral `#E76F51`, 4 Teal `#0D9488`, 5 Azure `#0284C7`, 6 Violet `#8B5CF6`,
7 Jade `#15803D`. Eye indices: 0 Twin, 1 Visor, 2 Triad, 3 Diamond, 4 Scanner,
5 Cross. Trait metadata retains the original palette name while Dormant.

### Events

```solidity
event Minted(address indexed owner, uint256 indexed tokenId, bytes32 seed);
event Beat(uint256 indexed tokenId, uint256 streak, uint256 totalBeats);
event Staked(uint256 indexed tokenId, uint256 amount, uint256 newBalance);
event Unstaked(uint256 indexed tokenId, uint256 amount, uint256 newBalance);
```

Mint also emits ERC-721 `Transfer(address(0), minter, tokenId)`. A rejected
receiver or failed stake/withdrawal reverts all state and logs. There is no
dormancy event: time passage is enough to change `alive` and `tokenURI`.

### Application errors

| Error | Cause |
| --- | --- |
| `InvalidPulseToken()` | Zero or self token address at construction |
| `PulseTokenNotDeployed()` | Configured token address has no code at staking use |
| `AlreadyHasDrone()` | Caller has already minted |
| `MaxSupplyReached()` | All 4,096 IDs have been minted |
| `NoDrone()` | Caller tries to beat, stake or unstake before minting |
| `Soulbound()` | Transfer or approval attempt |
| `BeatTooSoon(uint256 nextBeatAt)` | Called before the 20-hour cooldown elapsed |
| `ZeroAmount()` | Stake or unstake amount is zero |
| `InsufficientStake(uint256 available, uint256 requested)` | Withdrawal exceeds caller's ledger balance |
| `UnexpectedTokenAmount()` | Inbound token balance did not rise by exactly the requested amount |
| `InvalidBatchStart()` | Pagination start is zero |
| `BatchTooLarge()` | Count exceeds 256 |

OpenZeppelin ERC-721 errors cover invalid/missing owners, IDs and receivers;
SafeERC20/Address errors and token reverts propagate from transfers;
`ReentrancyGuardReentrantCall()` rejects callbacks into state-changing methods.
Nonpayable dispatch rejects ETH without a custom application error.

### Frontend timing

At a pinned block timestamp `t`, next allowed heartbeat is
`lastBeatAt + 72000`. Expiry is `lastBeatAt + 172800`; Alive includes that exact
second. Show the warning when Alive with less than 21,600 seconds remaining.
The stored streak may be nonzero for a Dormant Drone: filter by `alive` to build
the active leaderboard. PULSE amounts should be handled as big integers; the
JSON `Staked` display string preserves fractional precision.
