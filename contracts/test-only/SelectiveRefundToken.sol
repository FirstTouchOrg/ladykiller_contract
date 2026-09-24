// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Test-only token that can reject transfers to one wallet.
contract SelectiveRefundToken is ERC20 {
    address public blockedRecipient;
    uint8 private immutable _tokenDecimals;

    constructor(uint8 tokenDecimals) ERC20("Refund Test Token", "RTT") {
        _tokenDecimals = tokenDecimals;
        _mint(msg.sender, 1_000_000 * (10 ** uint256(tokenDecimals)));
    }

    function decimals() public view override returns (uint8) {
        return _tokenDecimals;
    }

    function setBlockedRecipient(address recipient) external {
        blockedRecipient = recipient;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (to == blockedRecipient) revert("recipient blocked");
        super._update(from, to, value);
    }
}
