// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "../../src/LaunchToken.sol";
import {PulseDrone} from "../../src/PulseDrone.sol";

abstract contract PulseTestBase is Test {
    LaunchToken internal token;
    PulseDrone internal drone;
    address internal alice;
    address internal bob;
    address internal carol;

    function setUp() public virtual {
        vm.warp(1_000_000);
        vm.prevrandao(bytes32(uint256(12345)));
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");
        token = new LaunchToken();
        drone = new PulseDrone(address(token));
    }

    function _mintDrone(address wallet) internal returns (uint256 id) {
        vm.prank(wallet);
        id = drone.mint();
    }

    function _fundDrone(address wallet, uint256 amount) internal returns (uint256 id) {
        id = _mintDrone(wallet);
        token.transfer(wallet, amount);
        vm.prank(wallet);
        token.approve(address(drone), amount);
    }

    function _beatAfter(address wallet, uint256 elapsed) internal {
        vm.warp(vm.getBlockTimestamp() + elapsed);
        vm.prank(wallet);
        drone.beat();
    }
}
