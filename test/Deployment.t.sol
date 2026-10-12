// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {PulseDrone} from "../src/PulseDrone.sol";

/// @dev Local constructor simulation, not a script or a production factory.
contract LocalFactory {
    function deploy() external returns (LaunchToken token, PulseDrone drone) {
        token = new LaunchToken();
        drone = new PulseDrone(address(token));
    }
}

contract DeploymentTest is Test {
    function test_factoryOwnsWholeSupplyAndDroneIsFullyConfigured() public {
        LocalFactory factory = new LocalFactory();
        (LaunchToken token, PulseDrone drone) = factory.deploy();
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(factory)), 1e27);
        assertEq(token.balanceOf(address(drone)), 0);
        assertEq(address(drone.pulseToken()), address(token));
        assertEq(drone.totalStaked(), 0);
        assertEq(drone.totalMinted(), 0);
        assertEq(address(token).balance, 0);
        assertEq(address(drone).balance, 0);
        _checkRuntime(address(token).code);
        _checkRuntime(address(drone).code);
    }

    function test_noAdminRecoveryPauseBurnOrUpgradeSelectors() public {
        LaunchToken token = new LaunchToken();
        PulseDrone drone = new PulseDrone(address(token));
        string[8] memory signatures = [
            "owner()",
            "pause()",
            "upgradeTo(address)",
            "setPulseToken(address)",
            "withdraw(address,uint256)",
            "recoverERC20(address,uint256)",
            "burn(uint256)",
            "initialize(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            (bool ok,) = address(drone).call(abi.encodeWithSignature(signatures[i], address(token), 1));
            assertFalse(ok);
        }
    }

    function _checkRuntime(bytes memory code) private pure {
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
        }
    }
}
