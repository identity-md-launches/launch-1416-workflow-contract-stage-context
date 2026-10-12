// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PulseTestBase} from "./helpers/PulseTestBase.sol";
import {PulseDrone} from "../src/PulseDrone.sol";
import {AdversarialToken} from "./helpers/Adversaries.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract PulseStakingTest is PulseTestBase {
    function test_stakePartialUnstakeAndInstantFullUnstake() public {
        _fundDrone(alice, 2000 ether);
        vm.expectEmit(true, false, false, true, address(drone));
        emit PulseDrone.Staked(1, 1500 ether, 1500 ether);
        vm.prank(alice);
        drone.stake(1500 ether);
        assertEq(drone.stateOf(1).staked, 1500 ether);
        assertEq(drone.totalStaked(), 1500 ether);
        assertEq(token.balanceOf(address(drone)), 1500 ether);
        assertEq(token.balanceOf(alice), 500 ether);
        assertEq(uint8(drone.stateOf(1).rank), uint8(PulseDrone.Rank.Worker));
        vm.expectEmit(true, false, false, true, address(drone));
        emit PulseDrone.Unstaked(1, 501 ether, 999 ether);
        vm.prank(alice);
        drone.unstake(501 ether);
        assertEq(uint8(drone.stateOf(1).rank), uint8(PulseDrone.Rank.Larva));
        vm.prank(alice);
        drone.unstake(999 ether);
        assertEq(drone.totalStaked(), 0);
        assertEq(drone.stateOf(1).staked, 0);
        assertEq(token.balanceOf(alice), 2000 ether);
        assertEq(drone.stateOf(1).totalBeats, 1);
    }

    function test_stakeAndUnstakeDoNotReviveDormantDrone() public {
        _fundDrone(alice, 100 ether);
        uint256 lastBeat = drone.stateOf(1).lastBeatAt;
        vm.warp(lastBeat + 100 days);
        vm.startPrank(alice);
        drone.stake(100 ether);
        drone.unstake(100 ether);
        vm.stopPrank();
        assertFalse(drone.stateOf(1).alive);
        assertEq(drone.stateOf(1).lastBeatAt, lastBeat);
        assertEq(token.balanceOf(alice), 100 ether);
    }

    function test_invalidAmountsAndOnlyCallerStake() public {
        vm.startPrank(alice);
        vm.expectRevert(PulseDrone.NoDrone.selector);
        drone.stake(1);
        vm.expectRevert(PulseDrone.NoDrone.selector);
        drone.unstake(1);
        vm.stopPrank();
        _fundDrone(alice, 100 ether);
        _mintDrone(bob);
        vm.startPrank(alice);
        vm.expectRevert(PulseDrone.ZeroAmount.selector);
        drone.stake(0);
        vm.expectRevert(PulseDrone.ZeroAmount.selector);
        drone.unstake(0);
        drone.stake(100 ether);
        vm.expectRevert(abi.encodeWithSelector(PulseDrone.InsufficientStake.selector, 100 ether, 100 ether + 1));
        drone.unstake(100 ether + 1);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(PulseDrone.InsufficientStake.selector, 0, 1));
        vm.prank(bob);
        drone.unstake(1);
        assertEq(drone.stateOf(1).staked, 100 ether);
        assertEq(drone.stateOf(2).staked, 0);
    }

    function test_failedAllowanceAndBalanceRollBackAccounting() public {
        _mintDrone(alice);
        token.transfer(alice, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(drone), 0, 1));
        vm.prank(alice);
        drone.stake(1);
        vm.prank(alice);
        token.approve(address(drone), 11 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10 ether, 11 ether)
        );
        vm.prank(alice);
        drone.stake(11 ether);
        assertEq(drone.totalStaked(), 0);
        assertEq(drone.stateOf(1).staked, 0);
        assertEq(token.allowance(alice, address(drone)), 11 ether);
        assertEq(token.balanceOf(address(drone)), 0);
    }

    function test_rankThresholdsAndOneMinorUnitBelow() public view {
        uint256[4] memory thresholds = [uint256(1000 ether), 100_000 ether, 1_000_000 ether, 10_000_000 ether];
        assertEq(uint8(drone.rankOf(0)), 0);
        for (uint8 i; i < 4; ++i) {
            assertEq(uint8(drone.rankOf(thresholds[i] - 1)), i);
            assertEq(uint8(drone.rankOf(thresholds[i])), i + 1);
            assertEq(uint8(drone.rankOf(thresholds[i] + 1)), i + 1);
        }
        assertEq(uint8(drone.rankOf(type(uint256).max)), 4);
    }

    function test_allRanksUpdateWhenDepositingAndWithdrawing() public {
        _fundDrone(alice, 10_000_000 ether);
        uint256[4] memory thresholds = [uint256(1000 ether), 100_000 ether, 1_000_000 ether, 10_000_000 ether];
        vm.startPrank(alice);
        uint256 deposited;
        for (uint8 i; i < 4; ++i) {
            drone.stake(thresholds[i] - deposited);
            deposited = thresholds[i];
            assertEq(uint8(drone.stateOf(1).rank), i + 1);
        }
        for (uint256 i = 4; i > 0; --i) {
            uint256 next = thresholds[i - 1] - 1;
            drone.unstake(deposited - next);
            deposited = next;
            assertEq(uint8(drone.stateOf(1).rank), i - 1);
        }
        vm.stopPrank();
    }

    function testFuzz_twoUserConservationAndDonations(uint96 rawA, uint96 rawB, uint96 rawWithdrawal) public {
        uint256 a = bound(uint256(rawA), 1, 100_000_000 ether);
        uint256 b = bound(uint256(rawB), 1, 100_000_000 ether);
        uint256 withdrawal = bound(uint256(rawWithdrawal), 1, a);
        _fundDrone(alice, a);
        _fundDrone(bob, b);
        vm.prank(alice);
        drone.stake(a);
        vm.prank(bob);
        drone.stake(b);
        token.transfer(address(drone), 7 ether);
        vm.prank(alice);
        drone.unstake(withdrawal);
        assertEq(drone.stateOf(1).staked, a - withdrawal);
        assertEq(drone.stateOf(2).staked, b);
        assertEq(drone.totalStaked(), a + b - withdrawal);
        assertEq(token.balanceOf(address(drone)), drone.totalStaked() + 7 ether);
        assertEq(token.balanceOf(alice), withdrawal);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), 1e27);
    }

    function test_tokenIsImmutableAndHasNoAdminSetter() public {
        assertEq(address(drone.pulseToken()), address(token));
        bytes memory call = abi.encodeWithSignature("setPulseToken(address)", address(token));
        (bool deployerCanSet,) = address(drone).call(call);
        vm.prank(alice);
        (bool userCanSet,) = address(drone).call(call);
        assertFalse(deployerCanSet);
        assertFalse(userCanSet);
        assertEq(address(drone.pulseToken()), address(token));
    }

    function test_constructorAllowsUndeployedTokenAndFirstUseHasClearError() public {
        address futureToken = makeAddr("future token used only for constructor test");
        PulseDrone futureDrone = new PulseDrone(futureToken);
        assertEq(address(futureDrone.pulseToken()), futureToken);
        vm.prank(alice);
        futureDrone.mint();
        vm.expectRevert(PulseDrone.PulseTokenNotDeployed.selector);
        vm.prank(alice);
        futureDrone.stake(1);
        assertEq(futureDrone.totalStaked(), 0);
        vm.expectRevert(PulseDrone.InvalidPulseToken.selector);
        new PulseDrone(address(0));
    }

    function test_falseReturnDepositAndWithdrawalRollBack() public {
        (AdversarialToken mock, PulseDrone vault) = _mockVault();
        mock.configure(AdversarialToken.Mode.FalseReturn, address(0), "");
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(mock)));
        vm.prank(alice);
        vault.stake(100 ether);
        assertEq(vault.totalStaked(), 0);
        assertEq(vault.stateOf(1).staked, 0);
        mock.configure(AdversarialToken.Mode.Normal, address(0), "");
        vm.prank(alice);
        vault.stake(100 ether);
        mock.configure(AdversarialToken.Mode.FalseReturn, address(0), "");
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(mock)));
        vm.prank(alice);
        vault.unstake(100 ether);
        assertEq(vault.totalStaked(), 100 ether);
        assertEq(vault.stateOf(1).staked, 100 ether);
        assertEq(mock.balanceOf(address(vault)), 100 ether);
    }

    function test_revertingTokenPreservesWithdrawalAndCanRetry() public {
        (AdversarialToken mock, PulseDrone vault) = _mockVault();
        vm.prank(alice);
        vault.stake(100 ether);
        mock.configure(AdversarialToken.Mode.RevertTransfer, address(0), "");
        vm.expectRevert(AdversarialToken.TransferRejected.selector);
        vm.prank(alice);
        vault.unstake(100 ether);
        assertEq(vault.stateOf(1).staked, 100 ether);
        mock.configure(AdversarialToken.Mode.Normal, address(0), "");
        vm.prank(alice);
        vault.unstake(100 ether);
        assertEq(vault.totalStaked(), 0);
        assertEq(mock.balanceOf(alice), 100 ether);
    }

    function test_feeOnTransferDepositRejectedAtomically() public {
        (AdversarialToken mock, PulseDrone vault) = _mockVault();
        mock.configure(AdversarialToken.Mode.Fee, address(0), "");
        vm.expectRevert(PulseDrone.UnexpectedTokenAmount.selector);
        vm.prank(alice);
        vault.stake(100 ether);
        assertEq(vault.totalStaked(), 0);
        assertEq(mock.balanceOf(address(vault)), 0);
        assertEq(mock.balanceOf(alice), 100 ether);
        assertEq(mock.allowance(alice, address(vault)), 100 ether);
    }

    function test_optionalReturnTokenWorksThroughSafeERC20() public {
        (AdversarialToken mock, PulseDrone vault) = _mockVault();
        mock.configure(AdversarialToken.Mode.NoReturn, address(0), "");
        vm.prank(alice);
        vault.stake(100 ether);
        vm.prank(alice);
        vault.unstake(100 ether);
        assertEq(vault.totalStaked(), 0);
        assertEq(mock.balanceOf(alice), 100 ether);
    }

    function test_reentrantTokenCannotEnterAnyMutationDuringDepositOrWithdrawal() public {
        (AdversarialToken mock, PulseDrone vault) = _mockVault();
        bytes[4] memory calls = [
            abi.encodeCall(vault.mint, ()),
            abi.encodeCall(vault.beat, ()),
            abi.encodeCall(vault.stake, (1)),
            abi.encodeCall(vault.unstake, (1))
        ];
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(alice);
            mock.approve(address(vault), 100 ether);
            mock.configure(AdversarialToken.Mode.Callback, address(vault), calls[i]);
            vm.prank(alice);
            vault.stake(100 ether);
            assertFalse(mock.callbackSucceeded());
            assertEq(bytes4(mock.callbackResult()), ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
            vm.prank(alice);
            vault.unstake(100 ether);
            assertFalse(mock.callbackSucceeded());
            assertEq(bytes4(mock.callbackResult()), ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
            assertEq(mock.balanceOf(alice), 100 ether);
            assertEq(vault.totalStaked(), 0);
        }
    }

    function _mockVault() private returns (AdversarialToken mock, PulseDrone vault) {
        mock = new AdversarialToken();
        vault = new PulseDrone(address(mock));
        mock.transfer(alice, 100 ether);
        vm.startPrank(alice);
        vault.mint();
        mock.approve(address(vault), 100 ether);
        vm.stopPrank();
    }
}
