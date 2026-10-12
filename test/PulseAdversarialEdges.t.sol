// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PulseTestBase} from "./helpers/PulseTestBase.sol";
import {PulseDrone} from "src/PulseDrone.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

/// forge-config: default.fuzz.runs = 1000
contract PulseAdversarialEdgesTest is PulseTestBase {
    function test_fullSupplyCanBeStakedAndRecoveredWhileDormant() public {
        _fundDrone(alice, 1e27);
        vm.prank(alice);
        drone.stake(1e27);
        assertEq(drone.totalStaked(), 1e27);
        assertEq(token.balanceOf(address(drone)), 1e27);
        assertEq(uint8(drone.stateOf(1).rank), uint8(PulseDrone.Rank.QueensGuard));
        vm.warp(vm.getBlockTimestamp() + 49 hours);
        vm.prank(alice);
        drone.unstake(1e27);
        assertEq(drone.totalStaked(), 0);
        assertEq(token.balanceOf(alice), 1e27);
        assertEq(token.balanceOf(address(drone)), 0);
        assertFalse(drone.stateOf(1).alive);
    }

    function test_oneWeiStakeRoundTrip() public {
        _fundDrone(alice, 1);
        bytes memory beforeState = abi.encode(drone.stateOf(1));
        vm.startPrank(alice);
        drone.stake(1);
        assertEq(drone.stateOf(1).staked, 1);
        assertEq(drone.totalStaked(), 1);
        drone.unstake(1);
        vm.stopPrank();
        assertEq(abi.encode(drone.stateOf(1)), beforeState);
        assertEq(token.balanceOf(alice), 1);
        assertEq(drone.totalStaked(), 0);
    }

    function test_revokingApprovalDoesNotPreventWithdrawal() public {
        _fundDrone(alice, 10 ether);
        vm.startPrank(alice);
        drone.stake(10 ether);
        token.approve(address(drone), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(drone), 0, 1));
        drone.stake(1);
        assertEq(drone.stateOf(1).staked, 10 ether);
        drone.unstake(10 ether);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(drone.totalStaked(), 0);
    }

    function test_tokenCodeDisappearingPreservesClaimAndAllowsRetry() public {
        _fundDrone(alice, 10 ether);
        vm.prank(alice);
        drone.stake(10 ether);
        bytes memory runtime = address(token).code;
        bytes memory beforeState = abi.encode(drone.stateOf(1));
        vm.etch(address(token), "");
        vm.expectRevert(PulseDrone.PulseTokenNotDeployed.selector);
        vm.prank(alice);
        drone.unstake(10 ether);
        assertEq(abi.encode(drone.stateOf(1)), beforeState);
        assertEq(drone.totalStaked(), 10 ether);
        vm.etch(address(token), runtime);
        vm.prank(alice);
        drone.unstake(10 ether);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(drone.totalStaked(), 0);
    }

    function test_maximumDepositInputRevertsWithoutChangingBalances() public {
        _fundDrone(alice, 1e27);
        vm.prank(alice);
        token.approve(address(drone), type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1e27, type(uint256).max)
        );
        vm.prank(alice);
        drone.stake(type(uint256).max);
        assertEq(drone.totalStaked(), 0);
        assertEq(drone.stateOf(1).staked, 0);
        assertEq(token.balanceOf(alice), 1e27);
        assertEq(token.balanceOf(address(drone)), 0);
    }

    function testFuzz_failedDepositPreservesExistingStake(uint256 rawStake, uint256 rawExcess) public {
        uint256 amount = bound(rawStake, 1, 1e27);
        _fundDrone(alice, amount);
        vm.startPrank(alice);
        drone.stake(amount);
        // Finite approval must also be restored if transferFrom spends it before failing.
        uint256 excess = bound(rawExcess, 1, type(uint256).max - amount);
        token.approve(address(drone), excess);
        bytes memory beforeState = abi.encode(drone.stateOf(1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, excess));
        drone.stake(excess);
        vm.stopPrank();
        assertEq(abi.encode(drone.stateOf(1)), beforeState);
        assertEq(drone.totalStaked(), amount);
        assertEq(token.balanceOf(address(drone)), amount);
        assertEq(token.allowance(alice, address(drone)), excess);
    }

    function testFuzz_unstakeCannotExceedCallerClaim(uint256 rawStake, uint256 rawExcess) public {
        uint256 amount = bound(rawStake, 1, 1e27);
        uint256 requested = bound(rawExcess, amount + 1, type(uint256).max);
        _fundDrone(alice, amount);
        vm.prank(alice);
        drone.stake(amount);
        bytes memory beforeState = abi.encode(drone.stateOf(1));
        vm.expectRevert(abi.encodeWithSelector(PulseDrone.InsufficientStake.selector, amount, requested));
        vm.prank(alice);
        drone.unstake(requested);
        assertEq(abi.encode(drone.stateOf(1)), beforeState);
        assertEq(drone.totalStaked(), amount);
        assertEq(token.balanceOf(address(drone)), amount);
    }

    function testFuzz_paginationReflectsIndependentOwnersAndLiveState(uint8 rawStart, uint16 rawCount) public {
        _fundDrone(alice, 1000 ether);
        _mintDrone(bob);
        _mintDrone(carol);
        vm.prank(alice);
        drone.stake(1000 ether);
        vm.warp(vm.getBlockTimestamp() + 49 hours);
        vm.prank(bob);
        drone.beat();
        uint256 start = bound(rawStart, 1, 5);
        uint256 count = bound(rawCount, 0, 256);
        PulseDrone.DroneState[] memory page = drone.getDrones(start, count);
        uint256 expectedLength = start > 3 ? 0 : (count < 4 - start ? count : 4 - start);
        assertEq(page.length, expectedLength);
        for (uint256 i; i < page.length; ++i) {
            uint256 id = start + i;
            assertEq(abi.encode(page[i]), abi.encode(drone.stateOf(id)));
            assertEq(page[i].owner, id == 1 ? alice : id == 2 ? bob : carol);
            assertEq(page[i].alive, id == 2);
            assertEq(page[i].staked, id == 1 ? 1000 ether : 0);
        }
    }
}
