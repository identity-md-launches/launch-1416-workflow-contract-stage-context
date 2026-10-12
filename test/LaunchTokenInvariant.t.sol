// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {LaunchToken} from "src/LaunchToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

/// @dev Closed actor set: all supply starts here and every successful transfer stays here.
contract LaunchTokenHandler is Test {
    LaunchToken public immutable token;
    address[4] public actors;
    uint256[4] public balances;
    mapping(uint256 => mapping(uint256 => uint256)) public allowances;

    constructor(LaunchToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        balances[0] = 1e27;
    }

    function approve(uint8 owner, uint8 spender, uint256 raw, bool unlimited) external {
        uint256 i = owner % 4;
        uint256 j = spender % 4;
        uint256 amount = unlimited ? type(uint256).max : bound(raw, 0, 1e27);
        vm.prank(actors[i]);
        assertTrue(token.approve(actors[j], amount));
        allowances[i][j] = amount;
    }

    function transfer(uint8 from, uint8 to, uint256 raw) external {
        uint256 i = from % 4;
        uint256 j = to % 4;
        uint256 amount = bound(raw, 0, balances[i]);
        vm.prank(actors[i]);
        assertTrue(token.transfer(actors[j], amount));
        balances[i] -= amount;
        balances[j] += amount;
    }

    function delegatedTransfer(uint8 from, uint8 to, uint8 spender, uint256 raw) external {
        uint256 i = from % 4;
        uint256 j = to % 4;
        uint256 k = spender % 4;
        uint256 limit = balances[i] < allowances[i][k] ? balances[i] : allowances[i][k];
        uint256 amount = bound(raw, 0, limit);
        vm.prank(actors[k]);
        assertTrue(token.transferFrom(actors[i], actors[j], amount));
        balances[i] -= amount;
        balances[j] += amount;
        if (allowances[i][k] != type(uint256).max) allowances[i][k] -= amount;
    }

    function rejectedTransfer(uint8 from, bool zeroRecipient) external {
        uint256 i = from % 4;
        address to = zeroRecipient ? address(0) : actors[(i + 1) % 4];
        uint256 amount = zeroRecipient ? 0 : balances[i] + 1;
        bytes memory expected = zeroRecipient
            ? abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
            : abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, actors[i], balances[i], amount);
        vm.prank(actors[i]);
        (bool ok, bytes memory result) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        assertFalse(ok);
        assertEq(result, expected);
    }

    function rejectedDelegatedTransfer(uint8 from, uint8 spender, uint256 raw) external {
        uint256 i = from % 4;
        uint256 k = spender % 4;
        uint256 allowance = bound(raw, 0, 1e27);
        vm.prank(actors[i]);
        assertTrue(token.approve(actors[k], allowance));
        allowances[i][k] = allowance;
        vm.prank(actors[k]);
        (bool ok, bytes memory result) =
            address(token).call(abi.encodeCall(token.transferFrom, (actors[i], actors[(i + 1) % 4], allowance + 1)));
        assertFalse(ok);
        assertEq(
            result,
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, actors[k], allowance, allowance + 1
            )
        );
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
contract LaunchTokenInvariantTest is StdInvariant, Test {
    LaunchToken private token;
    LaunchTokenHandler private handler;
    address[4] private actors;

    function setUp() public {
        token = new LaunchToken();
        for (uint256 i; i < 4; ++i) {
            actors[i] = makeAddr(string.concat("token actor ", vm.toString(i)));
        }
        token.transfer(actors[0], 1e27);
        handler = new LaunchTokenHandler(token, actors);
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = LaunchTokenHandler.approve.selector;
        selectors[1] = LaunchTokenHandler.transfer.selector;
        selectors[2] = LaunchTokenHandler.delegatedTransfer.selector;
        selectors[3] = LaunchTokenHandler.rejectedTransfer.selector;
        selectors[4] = LaunchTokenHandler.rejectedDelegatedTransfer.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_fixedSupplyBalancesAndAuthorization() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.balances(i));
            sum += token.balanceOf(actors[i]);
            for (uint256 j; j < 4; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.allowances(i, j));
            }
        }
        assertEq(sum, 1e27);
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }
}
