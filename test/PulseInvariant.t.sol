// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {PulseDrone} from "../src/PulseDrone.sol";

contract PulseHandler is Test {
    LaunchToken public immutable token;
    PulseDrone public immutable drone;
    address[4] public actors;
    uint256[4] public deposited;
    uint256[4] public donated;
    uint256[4] public streak;
    uint256[4] public bestStreak;
    uint256[4] public totalBeats;
    uint256[4] public lastBeatAt;
    bytes32[4] public seeds;

    constructor(LaunchToken token_, PulseDrone drone_, address[4] memory actors_) {
        token = token_;
        drone = drone_;
        actors = actors_;
        for (uint256 i; i < actors.length; ++i) {
            PulseDrone.DroneState memory initial = drone.stateOf(i + 1);
            streak[i] = 1;
            bestStreak[i] = 1;
            totalBeats[i] = 1;
            lastBeatAt[i] = initial.lastBeatAt;
            seeds[i] = initial.seed;
        }
    }

    function deposit(uint8 who, uint96 rawAmount) external {
        uint256 i = uint256(who) % 4;
        uint256 balance = token.balanceOf(actors[i]);
        if (balance == 0) return;
        uint256 amount = bound(uint256(rawAmount), 1, balance);
        vm.startPrank(actors[i]);
        token.approve(address(drone), amount);
        drone.stake(amount);
        vm.stopPrank();
        deposited[i] += amount;
    }

    function withdraw(uint8 who, uint96 rawAmount) external {
        uint256 i = uint256(who) % 4;
        if (deposited[i] == 0) return;
        uint256 amount = bound(uint256(rawAmount), 1, deposited[i]);
        vm.prank(actors[i]);
        drone.unstake(amount);
        deposited[i] -= amount;
    }

    function donate(uint8 who, uint96 rawAmount) external {
        uint256 i = uint256(who) % 4;
        uint256 balance = token.balanceOf(actors[i]);
        if (balance == 0) return;
        uint256 amount = bound(uint256(rawAmount), 1, balance);
        vm.prank(actors[i]);
        token.transfer(address(drone), amount);
        donated[i] += amount;
    }

    function heartbeat(uint8 who, uint32 rawGap) external {
        uint256 i = uint256(who) % 4;
        uint256 nextTime = vm.getBlockTimestamp() + bound(uint256(rawGap), 0, 72 hours);
        vm.warp(nextTime);
        uint256 elapsed = nextTime - lastBeatAt[i];
        if (elapsed < 20 hours) return;
        vm.prank(actors[i]);
        drone.beat();
        streak[i] = elapsed <= 48 hours ? streak[i] + 1 : 1;
        if (streak[i] > bestStreak[i]) bestStreak[i] = streak[i];
        ++totalBeats[i];
        lastBeatAt[i] = nextTime;
    }

    function forbiddenTransfer(uint8 who) external {
        uint256 i = uint256(who) % 4;
        vm.prank(actors[i]);
        (bool ok,) = address(drone).call(abi.encodeCall(drone.transferFrom, (actors[i], actors[(i + 1) % 4], i + 1)));
        assertFalse(ok);
    }

    // Failed calls are deliberately interleaved with funded calls: their effects must be atomic.
    function rejectedMutation(uint8 who, uint8 operation) external {
        uint256 i = uint256(who) % 4;
        bytes memory data;
        bytes memory expected;
        if (operation % 4 == 0) {
            data = abi.encodeCall(drone.mint, ());
            expected = abi.encodeWithSelector(PulseDrone.AlreadyHasDrone.selector);
        } else if (operation % 4 == 1) {
            data = abi.encodeCall(drone.stake, (0));
            expected = abi.encodeWithSelector(PulseDrone.ZeroAmount.selector);
        } else if (operation % 4 == 2) {
            data = abi.encodeCall(drone.unstake, (deposited[i] + 1));
            expected = abi.encodeWithSelector(PulseDrone.InsufficientStake.selector, deposited[i], deposited[i] + 1);
        } else {
            vm.prank(actors[i]);
            token.approve(address(drone), 0);
            data = abi.encodeCall(drone.stake, (1));
            expected =
                abi.encodeWithSignature("ERC20InsufficientAllowance(address,uint256,uint256)", address(drone), 0, 1);
        }
        vm.prank(actors[i]);
        (bool ok, bytes memory result) = address(drone).call(data);
        assertFalse(ok);
        assertEq(result, expected);
    }

    function roundTrip(uint8 who) external {
        uint256 i = uint256(who) % 4;
        uint256 amount = token.balanceOf(actors[i]);
        if (amount == 0) return;
        bytes memory beforeState = abi.encode(drone.stateOf(i + 1));
        uint256 beforeTotal = drone.totalStaked();
        uint256 beforeCustody = token.balanceOf(address(drone));
        vm.startPrank(actors[i]);
        token.approve(address(drone), amount);
        drone.stake(amount);
        drone.unstake(amount);
        vm.stopPrank();
        assertEq(token.balanceOf(actors[i]), amount);
        assertEq(token.balanceOf(address(drone)), beforeCustody);
        assertEq(drone.totalStaked(), beforeTotal);
        assertEq(abi.encode(drone.stateOf(i + 1)), beforeState);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
contract PulseInvariantTest is StdInvariant, Test {
    LaunchToken private token;
    PulseDrone private drone;
    PulseHandler private handler;
    address[4] private actors;
    uint256 private constant INITIAL_BALANCE = 100_000_000 ether;

    function setUp() public {
        vm.warp(1_000_000);
        token = new LaunchToken();
        drone = new PulseDrone(address(token));
        for (uint256 i; i < 4; ++i) {
            actors[i] = makeAddr(string.concat("invariant actor ", vm.toString(i)));
            token.transfer(actors[i], INITIAL_BALANCE);
            vm.prank(actors[i]);
            drone.mint();
        }
        handler = new PulseHandler(token, drone, actors);
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = PulseHandler.deposit.selector;
        selectors[1] = PulseHandler.withdraw.selector;
        selectors[2] = PulseHandler.donate.selector;
        selectors[3] = PulseHandler.heartbeat.selector;
        selectors[4] = PulseHandler.forbiddenTransfer.selector;
        selectors[5] = PulseHandler.rejectedMutation.selector;
        selectors[6] = PulseHandler.roundTrip.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_fundsAndDroneStateMatchIndependentLedger() public view {
        uint256 allDeposits;
        uint256 allDonations;
        uint256 circulating = token.balanceOf(address(this)) + token.balanceOf(address(drone));
        for (uint256 i; i < 4; ++i) {
            PulseDrone.DroneState memory state = drone.stateOf(i + 1);
            uint256 staked = handler.deposited(i);
            allDeposits += staked;
            allDonations += handler.donated(i);
            circulating += token.balanceOf(actors[i]);
            assertEq(state.staked, staked);
            assertEq(token.balanceOf(actors[i]) + staked + handler.donated(i), INITIAL_BALANCE);
            assertEq(state.owner, actors[i]);
            assertEq(drone.ownerOf(i + 1), actors[i]);
            assertEq(drone.droneOf(actors[i]), i + 1);
            assertEq(drone.balanceOf(actors[i]), 1);
            assertEq(state.seed, handler.seeds(i));
            assertEq(state.streak, handler.streak(i));
            assertEq(state.bestStreak, handler.bestStreak(i));
            assertEq(state.totalBeats, handler.totalBeats(i));
            assertEq(state.lastBeatAt, handler.lastBeatAt(i));
            assertEq(state.alive, vm.getBlockTimestamp() - handler.lastBeatAt(i) <= 48 hours);
            assertGe(state.bestStreak, state.streak);
            assertGe(state.totalBeats, state.bestStreak);
            uint8 rank = staked < 1000 ether
                ? 0
                : staked < 100_000 ether ? 1 : staked < 1_000_000 ether ? 2 : staked < 10_000_000 ether ? 3 : 4;
            assertEq(uint8(state.rank), rank);
        }
        assertEq(drone.totalStaked(), allDeposits);
        assertEq(token.balanceOf(address(drone)), allDeposits + allDonations);
        assertEq(token.totalSupply(), 1e27);
        assertEq(circulating, 1e27);
        assertEq(drone.totalMinted(), 4);
    }

    function afterInvariant() public {
        uint256 donations;
        for (uint256 i; i < 4; ++i) {
            uint256 amount = drone.stateOf(i + 1).staked;
            if (amount != 0) {
                vm.prank(actors[i]);
                drone.unstake(amount);
            }
            assertEq(token.balanceOf(actors[i]), INITIAL_BALANCE - handler.donated(i));
            donations += handler.donated(i);
        }
        assertEq(drone.totalStaked(), 0);
        assertEq(token.balanceOf(address(drone)), donations);
    }
}
