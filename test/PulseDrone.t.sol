// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PulseTestBase} from "./helpers/PulseTestBase.sol";
import {PulseDrone} from "../src/PulseDrone.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract PulseDroneTest is PulseTestBase {
    function test_mintInitializesOwnershipSeedAndFirstBeat() public {
        bytes32 expectedSeed = keccak256(abi.encode(uint256(1), alice, block.prevrandao));
        vm.expectEmit(true, true, false, true, address(drone));
        emit PulseDrone.Minted(alice, 1, expectedSeed);
        vm.expectEmit(true, false, false, true, address(drone));
        emit PulseDrone.Beat(1, 1, 1);
        assertEq(_mintDrone(alice), 1);
        PulseDrone.DroneState memory state = drone.stateOf(1);
        assertEq(state.owner, alice);
        assertEq(state.tokenId, 1);
        assertEq(state.seed, expectedSeed);
        assertEq(drone.ownerOf(1), alice);
        assertEq(drone.droneOf(alice), 1);
        assertEq(drone.balanceOf(alice), 1);
        assertEq(drone.totalMinted(), 1);
        assertEq(state.streak, 1);
        assertEq(state.bestStreak, 1);
        assertEq(state.totalBeats, 1);
        assertEq(state.lastBeatAt, vm.getBlockTimestamp());
        assertTrue(state.alive);
        assertEq(state.staked, 0);
        assertEq(uint8(state.rank), uint8(PulseDrone.Rank.Larva));
        assertEq(_mintDrone(bob), 2);
    }

    function test_duplicateMintAndSupplyCap() public {
        _mintDrone(alice);
        vm.expectRevert(PulseDrone.AlreadyHasDrone.selector);
        vm.prank(alice);
        drone.mint();
        for (uint256 i = 2; i <= 4096; ++i) {
            // Test-only distinct EOA addresses, never used as deployment configuration.
            address wallet = address(uint160(1_000_000 + i));
            assertEq(_mintDrone(wallet), i);
        }
        assertEq(drone.totalMinted(), 4096);
        PulseDrone.DroneState[] memory lastPage = drone.getDrones(3841, 256);
        assertEq(lastPage.length, 256);
        assertEq(lastPage[0].tokenId, 3841);
        assertEq(lastPage[255].tokenId, 4096);
        assertEq(drone.getDrones(4090, 256).length, 7);
        assertEq(drone.getDrones(4097, 256).length, 0);
        vm.expectRevert(PulseDrone.MaxSupplyReached.selector);
        vm.prank(bob);
        drone.mint();
        assertEq(drone.totalMinted(), 4096);
    }

    function test_erc721ViewsAndInvalidIds() public {
        assertEq(drone.name(), "Pulse Drone");
        assertEq(drone.symbol(), "DRONE");
        assertTrue(drone.supportsInterface(0x01ffc9a7));
        assertTrue(drone.supportsInterface(0x80ac58cd));
        assertTrue(drone.supportsInterface(0x5b5e139f));
        assertFalse(drone.supportsInterface(0xffffffff));
        assertEq(drone.droneOf(alice), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 0));
        drone.stateOf(0);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
        drone.tokenURI(1);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidOwner.selector, address(0)));
        drone.balanceOf(address(0));
        _mintDrone(alice);
        assertEq(drone.getApproved(1), address(0));
        assertFalse(drone.isApprovedForAll(alice, bob));
    }

    function test_allTransfersAndApprovalsRevertEvenForOwner() public {
        _mintDrone(alice);
        vm.startPrank(alice);
        vm.expectRevert(PulseDrone.Soulbound.selector);
        drone.transferFrom(alice, bob, 1);
        vm.expectRevert(PulseDrone.Soulbound.selector);
        drone.safeTransferFrom(alice, bob, 1);
        vm.expectRevert(PulseDrone.Soulbound.selector);
        drone.safeTransferFrom(alice, bob, 1, "data");
        vm.expectRevert(PulseDrone.Soulbound.selector);
        drone.transferFrom(alice, alice, 1);
        vm.expectRevert(PulseDrone.Soulbound.selector);
        drone.transferFrom(alice, address(0), 1);
        vm.expectRevert(PulseDrone.Soulbound.selector);
        drone.approve(bob, 1);
        vm.expectRevert(PulseDrone.Soulbound.selector);
        drone.approve(address(0), 1);
        vm.expectRevert(PulseDrone.Soulbound.selector);
        drone.setApprovalForAll(bob, true);
        vm.expectRevert(PulseDrone.Soulbound.selector);
        drone.setApprovalForAll(bob, false);
        vm.stopPrank();
        vm.expectRevert(PulseDrone.Soulbound.selector);
        vm.prank(carol);
        drone.transferFrom(alice, carol, 1);
        assertEq(drone.ownerOf(1), alice);
        assertEq(drone.balanceOf(bob), 0);
    }

    function test_noEthAccepted() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool mintOk,) = address(drone).call{value: 1}(abi.encodeCall(drone.mint, ()));
        assertFalse(mintOk);
        vm.prank(alice);
        (bool sendOk,) = address(drone).call{value: 1}("");
        assertFalse(sendOk);
        assertEq(drone.totalMinted(), 0);
    }

    function test_heartbeatCooldownAndExactTwentyHours() public {
        _mintDrone(alice);
        uint256 mintedAt = drone.stateOf(1).lastBeatAt;
        vm.expectRevert(abi.encodeWithSelector(PulseDrone.BeatTooSoon.selector, mintedAt + 20 hours));
        vm.prank(alice);
        drone.beat();
        vm.warp(mintedAt + 20 hours - 1);
        vm.expectRevert(abi.encodeWithSelector(PulseDrone.BeatTooSoon.selector, mintedAt + 20 hours));
        vm.prank(alice);
        drone.beat();
        vm.warp(mintedAt + 20 hours);
        vm.expectEmit(true, false, false, true, address(drone));
        emit PulseDrone.Beat(1, 2, 2);
        vm.prank(alice);
        drone.beat();
        assertEq(drone.stateOf(1).streak, 2);
        assertEq(drone.stateOf(1).lastBeatAt, mintedAt + 20 hours);
        vm.expectRevert(abi.encodeWithSelector(PulseDrone.BeatTooSoon.selector, mintedAt + 40 hours));
        vm.prank(alice);
        drone.beat();
    }

    function test_exactFortyEightHoursIsAliveAndContinuesStreak() public {
        _mintDrone(alice);
        vm.warp(vm.getBlockTimestamp() + 48 hours);
        assertTrue(drone.stateOf(1).alive);
        vm.prank(alice);
        drone.beat();
        assertEq(drone.stateOf(1).streak, 2);
        assertEq(drone.stateOf(1).bestStreak, 2);
    }

    function test_dormancyResetAndBestStreakPersists() public {
        _mintDrone(alice);
        _beatAfter(alice, 20 hours);
        _beatAfter(alice, 24 hours);
        vm.warp(vm.getBlockTimestamp() + 48 hours + 1);
        assertFalse(drone.stateOf(1).alive);
        assertEq(drone.stateOf(1).streak, 3);
        vm.prank(alice);
        drone.beat();
        PulseDrone.DroneState memory state = drone.stateOf(1);
        assertTrue(state.alive);
        assertEq(state.streak, 1);
        assertEq(state.bestStreak, 3);
        assertEq(state.totalBeats, 4);
        assertEq(state.lastBeatAt, vm.getBlockTimestamp());
    }

    function test_onlyDroneOwnerCanBeat() public {
        vm.expectRevert(PulseDrone.NoDrone.selector);
        vm.prank(alice);
        drone.beat();
        _mintDrone(alice);
        _mintDrone(bob);
        _beatAfter(bob, 20 hours);
        assertEq(drone.stateOf(1).streak, 1);
        assertEq(drone.stateOf(2).streak, 2);
    }

    function testFuzz_heartbeatTiming(uint32 rawGap) public {
        _mintDrone(alice);
        uint256 gap = bound(uint256(rawGap), 0, 365 days);
        uint256 lastBeat = drone.stateOf(1).lastBeatAt;
        vm.warp(lastBeat + gap);
        assertEq(drone.stateOf(1).alive, gap <= 48 hours);
        if (gap < 20 hours) {
            vm.expectRevert(abi.encodeWithSelector(PulseDrone.BeatTooSoon.selector, lastBeat + 20 hours));
            vm.prank(alice);
            drone.beat();
            assertEq(drone.stateOf(1).lastBeatAt, lastBeat);
            assertEq(drone.stateOf(1).totalBeats, 1);
        } else {
            vm.prank(alice);
            drone.beat();
            assertEq(drone.stateOf(1).streak, gap <= 48 hours ? 2 : 1);
            assertEq(drone.stateOf(1).bestStreak, gap <= 48 hours ? 2 : 1);
            assertEq(drone.stateOf(1).totalBeats, 2);
            assertTrue(drone.stateOf(1).alive);
        }
    }

    function test_paginationBoundsAndConsistency() public {
        assertEq(drone.getDrones(1, 256).length, 0);
        _mintDrone(alice);
        _mintDrone(bob);
        _mintDrone(carol);
        PulseDrone.DroneState[] memory page = drone.getDrones(2, 256);
        assertEq(page.length, 2);
        assertEq(abi.encode(page[0]), abi.encode(drone.stateOf(2)));
        assertEq(abi.encode(page[1]), abi.encode(drone.stateOf(3)));
        assertEq(drone.getDrones(1, 0).length, 0);
        assertEq(drone.getDrones(4, 1).length, 0);
        assertEq(drone.getDrones(type(uint256).max, 256).length, 0);
        vm.expectRevert(PulseDrone.InvalidBatchStart.selector);
        drone.getDrones(0, 1);
        vm.expectRevert(PulseDrone.BatchTooLarge.selector);
        drone.getDrones(1, 257);
        vm.expectRevert(PulseDrone.BatchTooLarge.selector);
        drone.getDrones(1, type(uint256).max);
    }

    function testFuzz_seedTraitsAreFixed(uint256 randomness) public {
        vm.prevrandao(randomness);
        _mintDrone(alice);
        PulseDrone.DroneState memory initial = drone.stateOf(1);
        uint256 seed = uint256(keccak256(abi.encode(uint256(1), alice, randomness)));
        uint256 roll = seed % 100;
        uint8 expectedCaste = roll < 40 ? 0 : roll < 70 ? 1 : roll < 90 ? 2 : 3;
        assertEq(uint8(initial.caste), expectedCaste);
        assertEq(initial.color, (seed >> 8) % 8);
        assertEq(initial.eyes, (seed >> 16) % 6);
        _beatAfter(alice, 49 hours);
        vm.prevrandao(bytes32(seed));
        PulseDrone.DroneState memory later = drone.stateOf(1);
        assertEq(later.seed, initial.seed);
        assertEq(uint8(later.caste), uint8(initial.caste));
        assertEq(later.color, initial.color);
        assertEq(later.eyes, initial.eyes);
    }
}
