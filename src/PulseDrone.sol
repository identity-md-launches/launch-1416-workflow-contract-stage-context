// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DroneArt} from "./lib/DroneArt.sol";

/// @notice One permanent Drone per wallet, kept alive by heartbeats and ranked by deposited PULSE.
/// @dev PULSE is bound at construction using the launch's $token reference. No administrative powers exist.
contract PulseDrone is ERC721, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_SUPPLY = 4096;
    uint256 public constant BEAT_COOLDOWN = 20 hours;
    uint256 public constant ALIVE_WINDOW = 48 hours;
    uint256 public constant MAX_BATCH_SIZE = 256;

    enum Caste {
        Worker,
        Scout,
        Guard,
        Builder
    }

    enum Rank {
        Larva,
        Worker,
        Guard,
        RoyalGuard,
        QueensGuard
    }

    struct Drone {
        bytes32 seed;
        uint256 streak;
        uint256 bestStreak;
        uint256 totalBeats;
        uint256 lastBeatAt;
        uint256 staked;
    }

    /// @notice A snapshot at the current block timestamp; enum and palette indices are zero-based.
    struct DroneState {
        uint256 tokenId;
        address owner;
        bytes32 seed;
        Caste caste;
        uint8 color;
        uint8 eyes;
        bool alive;
        uint256 streak;
        uint256 bestStreak;
        uint256 totalBeats;
        uint256 lastBeatAt;
        uint256 staked;
        Rank rank;
    }

    IERC20 public immutable pulseToken;
    uint256 public totalMinted;
    uint256 public totalStaked;
    mapping(address wallet => uint256 tokenId) public droneOf;
    mapping(uint256 tokenId => Drone) private _drones;

    error InvalidPulseToken();
    error PulseTokenNotDeployed();
    error AlreadyHasDrone();
    error MaxSupplyReached();
    error NoDrone();
    error Soulbound();
    error BeatTooSoon(uint256 nextBeatAt);
    error ZeroAmount();
    error InsufficientStake(uint256 available, uint256 requested);
    error UnexpectedTokenAmount();
    error InvalidBatchStart();
    error BatchTooLarge();

    event Minted(address indexed owner, uint256 indexed tokenId, bytes32 seed);
    event Beat(uint256 indexed tokenId, uint256 streak, uint256 totalBeats);
    event Staked(uint256 indexed tokenId, uint256 amount, uint256 newBalance);
    event Unstaked(uint256 indexed tokenId, uint256 amount, uint256 newBalance);

    /// @param pulseToken_ The launch token address ($token), fixed forever. Constructor makes no external calls.
    constructor(address pulseToken_) ERC721("Pulse Drone", "DRONE") {
        if (pulseToken_ == address(0) || pulseToken_ == address(this)) revert InvalidPulseToken();
        pulseToken = IERC20(pulseToken_);
    }

    /// @notice Mint a free Drone and record its first heartbeat. No ETH is accepted.
    function mint() external nonReentrant returns (uint256 tokenId) {
        if (droneOf[msg.sender] != 0) revert AlreadyHasDrone();
        if (totalMinted == MAX_SUPPLY) revert MaxSupplyReached();
        tokenId = ++totalMinted;
        bytes32 seed = keccak256(abi.encode(tokenId, msg.sender, block.prevrandao));
        droneOf[msg.sender] = tokenId;
        _drones[tokenId] = Drone(seed, 1, 1, 1, block.timestamp, 0);
        // Finalize state before the ERC-721 receiver callback; all mutation entry points share the guard.
        emit Minted(msg.sender, tokenId, seed);
        emit Beat(tokenId, 1, 1);
        _safeMint(msg.sender, tokenId);
    }

    /// @notice Beat after 20 hours. Exactly 48 hours preserves the streak; any later beat resets it to one.
    function beat() external nonReentrant {
        uint256 tokenId = _callerDrone();
        Drone storage drone = _drones[tokenId];
        uint256 elapsed = block.timestamp - drone.lastBeatAt;
        if (elapsed < BEAT_COOLDOWN) revert BeatTooSoon(drone.lastBeatAt + BEAT_COOLDOWN);
        drone.streak = elapsed <= ALIVE_WINDOW ? drone.streak + 1 : 1;
        if (drone.streak > drone.bestStreak) drone.bestStreak = drone.streak;
        ++drone.totalBeats;
        drone.lastBeatAt = block.timestamp;
        emit Beat(tokenId, drone.streak, drone.totalBeats);
    }

    /// @notice Deposit PULSE minor units. Staking never changes heartbeat state and pays no rewards.
    function stake(uint256 amount) external nonReentrant {
        uint256 tokenId = _callerDrone();
        if (amount == 0) revert ZeroAmount();
        _requireTokenCode();
        uint256 beforeBalance = pulseToken.balanceOf(address(this));
        Drone storage drone = _drones[tokenId];
        drone.staked += amount;
        totalStaked += amount;
        pulseToken.safeTransferFrom(msg.sender, address(this), amount);
        if (pulseToken.balanceOf(address(this)) != beforeBalance + amount) revert UnexpectedTokenAmount();
        emit Staked(tokenId, amount, drone.staked);
    }

    /// @notice Withdraw the caller's PULSE instantly, including while dormant.
    function unstake(uint256 amount) external nonReentrant {
        uint256 tokenId = _callerDrone();
        if (amount == 0) revert ZeroAmount();
        Drone storage drone = _drones[tokenId];
        if (amount > drone.staked) revert InsufficientStake(drone.staked, amount);
        _requireTokenCode();
        drone.staked -= amount;
        totalStaked -= amount;
        pulseToken.safeTransfer(msg.sender, amount);
        emit Unstaked(tokenId, amount, drone.staked);
    }

    function stateOf(uint256 tokenId) public view returns (DroneState memory state) {
        state.owner = _requireOwned(tokenId);
        Drone storage drone = _drones[tokenId];
        state.tokenId = tokenId;
        state.seed = drone.seed;
        uint256 seed = uint256(drone.seed);
        uint256 roll = seed % 100;
        state.caste = roll < 40 ? Caste.Worker : roll < 70 ? Caste.Scout : roll < 90 ? Caste.Guard : Caste.Builder;
        state.color = uint8((seed >> 8) % 8);
        state.eyes = uint8((seed >> 16) % 6);
        state.alive = block.timestamp - drone.lastBeatAt <= ALIVE_WINDOW;
        state.streak = drone.streak;
        state.bestStreak = drone.bestStreak;
        state.totalBeats = drone.totalBeats;
        state.lastBeatAt = drone.lastBeatAt;
        state.staked = drone.staked;
        state.rank = rankOf(drone.staked);
    }

    /// @notice Read consecutive token IDs starting at `start` (one-based), capped at the last minted ID.
    /// @dev Zero count or a start beyond the last ID returns an empty array. Start zero is invalid.
    function getDrones(uint256 start, uint256 count) external view returns (DroneState[] memory states) {
        if (start == 0) revert InvalidBatchStart();
        if (count > MAX_BATCH_SIZE) revert BatchTooLarge();
        if (start > totalMinted || count == 0) return new DroneState[](0);
        uint256 available = totalMinted - start + 1;
        if (count > available) count = available;
        states = new DroneState[](count);
        for (uint256 i; i < count; ++i) {
            states[i] = stateOf(start + i);
        }
    }

    /// @param amount PULSE minor units (18 decimals), not whole tokens.
    function rankOf(uint256 amount) public pure returns (Rank) {
        if (amount >= 10_000_000 ether) return Rank.QueensGuard;
        if (amount >= 1_000_000 ether) return Rank.RoyalGuard;
        if (amount >= 100_000 ether) return Rank.Guard;
        if (amount >= 1_000 ether) return Rank.Worker;
        return Rank.Larva;
    }

    /// @notice Fully onchain base64 JSON containing base64 SVG; appearance reflects current state.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        DroneState memory state = stateOf(tokenId);
        return DroneArt.tokenURI(
            DroneArt.Metadata({
                tokenId: tokenId,
                caste: uint8(state.caste),
                color: state.color,
                eyes: state.eyes,
                alive: state.alive,
                streak: state.streak,
                bestStreak: state.bestStreak,
                totalBeats: state.totalBeats,
                rank: uint8(state.rank),
                staked: state.staked
            })
        );
    }

    function approve(address, uint256) public pure override {
        revert Soulbound();
    }

    function setApprovalForAll(address, bool) public pure override {
        revert Soulbound();
    }

    function transferFrom(address, address, uint256) public pure override {
        revert Soulbound();
    }

    // The inherited three-argument safeTransferFrom forwards here.
    function safeTransferFrom(address, address, uint256, bytes memory) public pure override {
        revert Soulbound();
    }

    /// @dev Also enforce soulbinding at the ERC-721 state transition layer.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        if (_ownerOf(tokenId) != address(0) || to == address(0)) revert Soulbound();
        return super._update(to, tokenId, auth);
    }

    function _callerDrone() private view returns (uint256 tokenId) {
        tokenId = droneOf[msg.sender];
        if (tokenId == 0) revert NoDrone();
    }

    function _requireTokenCode() private view {
        if (address(pulseToken).code.length == 0) revert PulseTokenNotDeployed();
    }
}
