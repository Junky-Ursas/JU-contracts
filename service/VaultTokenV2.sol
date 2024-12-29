// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title VaultToken - ERC20 Token for Vaults
interface IVaultManager {
    function handleVaultTokenTransfer(address from, address to, uint256 amount, address liqTokenAddress) external;

}

contract VaultTokenV2 is ERC20, Ownable {
    address internal liqTokenAddress;
    address internal vaultManager;
    /// @dev Constructor to initialize the VaultToken
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param owner The address of the owner
    constructor(string memory name, string memory symbol, address owner, address _liqTokenAddress, address _vaultManager) ERC20(name, symbol) Ownable(owner) {
        liqTokenAddress = _liqTokenAddress;
        vaultManager = _vaultManager;
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

    /// @dev Hook after token transfer
    function transfer(
        address to,
        uint256 value
    ) public virtual override returns (bool) {
         address owner = _msgSender();
        _transfer(owner, to, value);
        // Notify VaultManager about the transfer
        if (msg.sender != address(0) && to != address(0)) { // Exclude mint and burn
            IVaultManager(vaultManager).handleVaultTokenTransfer(msg.sender, to, value, liqTokenAddress);
        }
        return true;
    }

    function setVaultManager(address _vaultManager) external onlyOwner {
        vaultManager = _vaultManager;
    }

    function getVaultManager() external view returns (address) {
        return vaultManager;
    }

    function setLiqTokenAddress(address _liqTokenAddress) external onlyOwner {
        liqTokenAddress = _liqTokenAddress;
    }

    function getLiqTokenAddress() external view returns (address) {
        return liqTokenAddress;
    }

    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);
}