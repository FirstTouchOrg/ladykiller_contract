// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title LKR test token
/// @notice An 18-decimal token for testing the Ladykiller game on BSC Testnet.
contract LKRToken is ERC20, Ownable {
    constructor(address initialOwner, uint256 initialSupply)
        ERC20("LKR", "LKR")
        Ownable(initialOwner)
    {
        _mint(initialOwner, initialSupply);
    }

    /// @notice Mints additional test tokens. This function is for testnet use.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
