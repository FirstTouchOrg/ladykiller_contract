// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";

/// @notice VRF consumer with a coordinator that cannot be replaced after deployment.
/// @dev A new consumer must be deployed if Chainlink migrates its coordinator.
abstract contract FixedVRFConsumerBaseV2Plus is Ownable2Step {
    error OnlyCoordinatorCanFulfill(address have, address want);
    error ZeroAddress();
    error OwnershipRenunciationDisabled();

    IVRFCoordinatorV2Plus public immutable s_vrfCoordinator;

    constructor(address vrfCoordinator) Ownable(msg.sender) {
        if (vrfCoordinator == address(0)) revert ZeroAddress();
        s_vrfCoordinator = IVRFCoordinatorV2Plus(vrfCoordinator);
    }

    function renounceOwnership() public pure override {
        revert OwnershipRenunciationDisabled();
    }

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal virtual;

    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external {
        address coordinator = address(s_vrfCoordinator);
        if (msg.sender != coordinator) revert OnlyCoordinatorCanFulfill(msg.sender, coordinator);
        fulfillRandomWords(requestId, randomWords);
    }
}
