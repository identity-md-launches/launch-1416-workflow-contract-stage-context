// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {PulseDrone} from "../../src/PulseDrone.sol";

/// @dev Test-only ERC-20 covering failed/optional returns, fee deductions and reentrant callbacks.
contract AdversarialToken is ERC20 {
    enum Mode {
        Normal,
        FalseReturn,
        RevertTransfer,
        Fee,
        NoReturn,
        Callback
    }

    Mode public mode;
    address public callbackTarget;
    bytes public callbackData;
    bool public callbackSucceeded;
    bytes public callbackResult;

    error TransferRejected();

    constructor() ERC20("Test only", "TEST") {
        _mint(msg.sender, 1e27);
    }

    function configure(Mode mode_, address target_, bytes calldata data_) external {
        mode = mode_;
        callbackTarget = target_;
        callbackData = data_;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (mode == Mode.FalseReturn) return false;
        if (mode == Mode.RevertTransfer) revert TransferRejected();
        bool result = super.transfer(to, amount);
        _afterTransfer();
        return result;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (mode == Mode.FalseReturn) return false;
        if (mode == Mode.RevertTransfer) revert TransferRejected();
        bool result = super.transferFrom(from, to, amount);
        _afterTransfer();
        return result;
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (mode == Mode.Fee && from != address(0)) {
            uint256 fee = amount / 100;
            super._update(from, address(this), fee);
            super._update(from, to, amount - fee);
        } else {
            super._update(from, to, amount);
        }
    }

    function _afterTransfer() private {
        if (mode == Mode.Callback) {
            (callbackSucceeded, callbackResult) = callbackTarget.call(callbackData);
        }
        if (mode == Mode.NoReturn) {
            assembly ("memory-safe") {
                return(0, 0)
            }
        }
    }
}

contract DroneReceiver is IERC721Receiver {
    PulseDrone public immutable drone;
    bool public reject;
    bool public observedConsistentState;
    bytes4[4] public callbackErrors;

    error ReceiverRejected();

    constructor(PulseDrone drone_) {
        drone = drone_;
    }

    function setReject(bool value) external {
        reject = value;
    }

    function mintDrone() external returns (uint256) {
        return drone.mint();
    }

    function onERC721Received(address, address, uint256 id, bytes calldata) external returns (bytes4) {
        require(msg.sender == address(drone));
        if (reject) revert ReceiverRejected();
        PulseDrone.DroneState memory state = drone.stateOf(id);
        observedConsistentState = state.owner == address(this) && drone.droneOf(address(this)) == id
            && state.streak == 1 && state.totalBeats == 1 && state.alive;
        bytes[4] memory calls = [
            abi.encodeCall(drone.mint, ()),
            abi.encodeCall(drone.beat, ()),
            abi.encodeCall(drone.stake, (1)),
            abi.encodeCall(drone.unstake, (1))
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool ok, bytes memory response) = address(drone).call(calls[i]);
            require(!ok, "reentry unexpectedly worked");
            callbackErrors[i] = bytes4(response);
        }
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract MissingReceiver {
    function mintDrone(PulseDrone drone) external {
        drone.mint();
    }
}
