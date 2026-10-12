// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PulseTestBase} from "./helpers/PulseTestBase.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract LaunchTokenTest is PulseTestBase {
    function test_supplyAndMetadata() public view {
        assertEq(token.name(), "Pulse");
        assertEq(token.symbol(), "PULSE");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(this)), 1e27);
        assertEq(token.balanceOf(address(drone)), 0);
    }

    function testFuzz_transferConservesSupply(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, 1e27);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), 1e27 - amount);
        assertEq(token.totalSupply(), 1e27);
    }

    function test_allowanceAndTransferFrom() public {
        token.transfer(alice, 100 ether);
        vm.prank(alice);
        token.approve(bob, 40 ether);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, 15 ether));
        assertEq(token.balanceOf(alice), 85 ether);
        assertEq(token.balanceOf(carol), 15 ether);
        assertEq(token.allowance(alice, bob), 25 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 25 ether, 26 ether)
        );
        vm.prank(bob);
        token.transferFrom(alice, carol, 26 ether);
    }

    function test_invalidTransferAndNoPublicBurn() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
        (bool ok,) = address(token).call(abi.encodeWithSignature("burn(uint256)", 1));
        assertFalse(ok);
        assertEq(token.totalSupply(), 1e27);
    }

    function test_noPrivilegedMintUpgradeOrPause() public {
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "pause()",
            "setMinter(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], alice, 1 ether);
            (bool byDeployer,) = address(token).call(data);
            vm.prank(alice);
            (bool byUser,) = address(token).call(data);
            assertFalse(byDeployer);
            assertFalse(byUser);
            assertEq(token.totalSupply(), 1e27);
            assertEq(token.balanceOf(alice), 0);
        }
    }
}
