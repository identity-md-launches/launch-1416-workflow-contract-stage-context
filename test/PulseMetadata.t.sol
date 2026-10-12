// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PulseTestBase} from "./helpers/PulseTestBase.sol";
import {MetadataDecoder} from "./helpers/MetadataDecoder.sol";
import {DroneArt} from "../src/lib/DroneArt.sol";
import {PulseDrone} from "../src/PulseDrone.sol";

contract PulseMetadataTest is PulseTestBase {
    using MetadataDecoder for string;

    function test_aliveAndDormantMetadataAreValidJsonWithEmbeddedSvg() public {
        _mintDrone(alice);
        (string memory json, string memory svg) = _metadata(1);
        assertEq(vm.parseJsonString(json, ".name"), "DRONE-0001");
        assertEq(vm.parseJsonKeys(json, "$").length, 4);
        string[9] memory expected =
            ["Caste", "Color", "Eyes", "Status", "Streak", "Best Streak", "Total Beats", "Rank", "Staked"];
        for (uint256 i; i < expected.length; ++i) {
            assertEq(
                vm.parseJsonString(json, string.concat(".attributes[", vm.toString(i), "].trait_type")), expected[i]
            );
        }
        assertFalse(vm.keyExistsJson(json, ".attributes[9]"));
        PulseDrone.DroneState memory state = drone.stateOf(1);
        assertEq(vm.parseJsonString(json, ".attributes[0].value"), DroneArt.casteName(uint8(state.caste)));
        assertEq(vm.parseJsonString(json, ".attributes[1].value"), DroneArt.colorName(state.color));
        assertEq(vm.parseJsonString(json, ".attributes[2].value"), DroneArt.eyeName(state.eyes));
        assertEq(vm.parseJsonString(json, ".attributes[3].value"), "Alive");
        assertEq(vm.parseJsonUint(json, ".attributes[4].value"), 1);
        assertEq(vm.parseJsonUint(json, ".attributes[5].value"), 1);
        assertEq(vm.parseJsonUint(json, ".attributes[6].value"), 1);
        assertEq(vm.parseJsonString(json, ".attributes[7].value"), "Larva");
        assertEq(vm.parseJsonString(json, ".attributes[8].value"), "0");
        assertTrue(svg.contains('width="512" height="512"'));
        assertTrue(svg.contains('viewBox="0 0 512 512"'));
        assertTrue(svg.contains("<polygon"));
        assertTrue(svg.contains("<animate"));
        assertTrue(svg.contains('dur="4s"'));
        assertTrue(svg.contains("#F59E0B"));
        assertFalse(svg.contains("data-rank="));
        assertFalse(svg.contains("data-aura="));
        assertFalse(svg.contains("href="));
        assertFalse(svg.contains("<script"));
        vm.warp(drone.stateOf(1).lastBeatAt + 48 hours + 1);
        (string memory dormantJson, string memory dormantSvg) = _metadata(1);
        assertEq(vm.parseJsonString(dormantJson, ".attributes[3].value"), "Dormant");
        assertEq(
            vm.parseJsonString(dormantJson, ".attributes[0].value"), vm.parseJsonString(json, ".attributes[0].value")
        );
        assertEq(
            vm.parseJsonString(dormantJson, ".attributes[1].value"), vm.parseJsonString(json, ".attributes[1].value")
        );
        assertEq(
            vm.parseJsonString(dormantJson, ".attributes[2].value"), vm.parseJsonString(json, ".attributes[2].value")
        );
        assertTrue(dormantSvg.contains("#737373"));
        assertTrue(dormantSvg.contains("DORMANT"));
        assertFalse(dormantSvg.contains("<animate"));
        assertFalse(dormantSvg.contains("#F59E0B"));
        assertFalse(dormantSvg.contains("<filter"));
        vm.prank(alice);
        drone.beat();
        (, string memory revivedSvg) = _metadata(1);
        assertTrue(revivedSvg.contains("<animate"));
        assertTrue(revivedSvg.contains(DroneArt.palette(state.color)));
    }

    function test_aurasAtSevenThirtyAndHundredBeatsAndAfterReset() public {
        _mintDrone(alice);
        for (uint256 streak = 2; streak <= 100; ++streak) {
            _beatAfter(alice, 24 hours);
            if (streak == 6 || streak == 7 || streak == 29 || streak == 30 || streak == 99 || streak == 100) {
                (, string memory svg) = _metadata(1);
                assertEq(svg.contains('data-aura="1"'), streak >= 7);
                assertEq(svg.contains('data-aura="2"'), streak >= 30);
                assertEq(svg.contains('data-aura="3"'), streak >= 100);
            }
        }
        _beatAfter(alice, 49 hours);
        (string memory json, string memory resetSvg) = _metadata(1);
        assertFalse(resetSvg.contains("data-aura="));
        assertEq(vm.parseJsonUint(json, ".attributes[4].value"), 1);
        assertEq(vm.parseJsonUint(json, ".attributes[5].value"), 100);
        assertEq(vm.parseJsonUint(json, ".attributes[6].value"), 101);
    }

    function test_rankBadgeAndStakedAttributeUpdateExactly() public {
        _fundDrone(alice, 10_000_000 ether + 1);
        vm.prank(alice);
        drone.stake(10_000_000 ether + 1);
        (string memory json, string memory svg) = _metadata(1);
        assertEq(vm.parseJsonString(json, ".attributes[7].value"), "Queen's Guard");
        assertEq(vm.parseJsonString(json, ".attributes[8].value"), "10000000.000000000000000001");
        assertTrue(svg.contains("Queen's Guard"));
        assertTrue(svg.contains(">QG</text>"));
        vm.prank(alice);
        drone.unstake(10_000_000 ether + 1);
        (json, svg) = _metadata(1);
        assertEq(vm.parseJsonString(json, ".attributes[7].value"), "Larva");
        assertEq(vm.parseJsonString(json, ".attributes[8].value"), "0");
        assertFalse(svg.contains("data-rank="));
    }

    function test_allArtistVariantsRenderDistinctly() public pure {
        DroneArt.Metadata memory m;
        m.tokenId = 4096;
        m.alive = true;
        m.streak = 100;
        bytes32 previous;
        for (uint8 i; i < 8; ++i) {
            m.color = i;
            string memory svg = DroneArt.svg(m);
            assertTrue(svg.contains(DroneArt.palette(i)));
            assertNotEq(keccak256(bytes(svg)), previous);
            previous = keccak256(bytes(svg));
        }
        previous = bytes32(0);
        for (uint8 i; i < 6; ++i) {
            m.eyes = i;
            bytes32 current = keccak256(bytes(DroneArt.svg(m)));
            assertNotEq(current, previous);
            previous = current;
        }
        for (uint8 i; i < 4; ++i) {
            m.caste = i;
            string memory svg = DroneArt.svg(m);
            assertTrue(svg.contains(DroneArt.casteName(i)));
        }
        for (uint8 i = 1; i < 5; ++i) {
            m.rank = i;
            assertTrue(DroneArt.svg(m).contains(DroneArt.rankName(i)));
        }
    }

    function test_callSignsAndExactPulseFormatting() public pure {
        assertEq(DroneArt.callSign(1), "DRONE-0001");
        assertEq(DroneArt.callSign(9), "DRONE-0009");
        assertEq(DroneArt.callSign(10), "DRONE-0010");
        assertEq(DroneArt.callSign(99), "DRONE-0099");
        assertEq(DroneArt.callSign(100), "DRONE-0100");
        assertEq(DroneArt.callSign(999), "DRONE-0999");
        assertEq(DroneArt.callSign(1000), "DRONE-1000");
        assertEq(DroneArt.callSign(4096), "DRONE-4096");
        assertEq(DroneArt.formatPulse(0), "0");
        assertEq(DroneArt.formatPulse(1), "0.000000000000000001");
        assertEq(DroneArt.formatPulse(1 ether), "1");
        assertEq(DroneArt.formatPulse(1.5 ether), "1.500000000000000000");
        assertEq(DroneArt.formatPulse(1 ether - 1), "0.999999999999999999");
    }

    function _metadata(uint256 id) private view returns (string memory json, string memory svg) {
        json = drone.tokenURI(id).decodeURI("data:application/json;base64,");
        svg = vm.parseJsonString(json, ".image").decodeURI("data:image/svg+xml;base64,");
    }
}
