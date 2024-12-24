// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title VaultToken
/// @notice ERC20 token representing shares in liquidity vaults
/// @dev Implements mintable/burnable ERC20 token for vault share representation
contract VaultToken is ERC20, Ownable {
    /// @dev Constructor to initialize the VaultToken
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param owner The address of the owner
    constructor(string memory name, string memory symbol, address owner) ERC20(name, symbol) Ownable(owner) {
        transferOwnership(owner);
    }

    /// @dev Function to mint new tokens
    /// @param to The address to receive the tokens
    /// @param amount The amount of tokens to mint
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
        emit Mint(to, amount);
    }

    /// @dev Function to burn tokens
    /// @param from The address to burn tokens from
    /// @param amount The amount of tokens to burn
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
        emit Burn(from, amount);
    }

    /// @notice Emitted when new tokens are minted
    /// @param to Address receiving the tokens
    /// @param amount Amount of tokens minted
    event Mint(address indexed to, uint256 amount);

    /// @notice Emitted when tokens are burned
    /// @param from Address from which tokens are burned
    /// @param amount Amount of tokens burned
    event Burn(address indexed from, uint256 amount);
}