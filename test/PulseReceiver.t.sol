// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PulseTestBase} from "./helpers/PulseTestBase.sol";
import {DroneReceiver, MissingReceiver} from "./helpers/Adversaries.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract PulseReceiverTest is PulseTestBase {
    function test_receiverObservesCompleteStateAndCannotReenter() public {
        DroneReceiver receiver = new DroneReceiver(drone);
        assertEq(receiver.mintDrone(), 1);
        assertTrue(receiver.observedConsistentState());
        for (uint256 i; i < 4; ++i) {
            assertEq(receiver.callbackErrors(i), ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        }
        assertEq(drone.totalMinted(), 1);
        assertEq(drone.ownerOf(1), address(receiver));
        assertEq(drone.stateOf(1).totalBeats, 1);
    }

    function test_rejectedReceiverRollsBackAndCanRetry() public {
        DroneReceiver receiver = new DroneReceiver(drone);
        receiver.setReject(true);
        vm.expectRevert(DroneReceiver.ReceiverRejected.selector);
        receiver.mintDrone();
        assertEq(drone.totalMinted(), 0);
        assertEq(drone.droneOf(address(receiver)), 0);
        assertEq(drone.balanceOf(address(receiver)), 0);
        receiver.setReject(false);
        assertEq(receiver.mintDrone(), 1);
    }

    function test_contractWithoutReceiverCannotMint() public {
        MissingReceiver receiver = new MissingReceiver();
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(receiver)));
        receiver.mintDrone(drone);
        assertEq(drone.totalMinted(), 0);
    }
}
