// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BaseGameContract.sol";
import "./VaultToken.sol";

/// @title VaultManager - Manages Vaults and their liquidity
contract VaultManagerProxy is BaseGameContractProxy {
        /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    struct Vault {
        address vaultTokenAddress;
        uint256 totalBalance;
        uint256 totalVaultTokens;
    }

    struct VaultWithPrice {
        address vaultTokenAddress;
        address liqTokenAddress;
        uint256 totalBalance;
        uint256 totalVaultTokens;
        uint256 vaultTokenPrice; 
    }

    struct UserDeposit {
        uint256 initialAmount; 
        uint256 vaultTokens;
    }

    mapping(address => Vault) private vaults; 
    mapping(address => mapping(address => UserDeposit)) public userDeposits; 
    address[] private vaultAddresses; 

    event VaultCreated(
        address indexed liqTokenAddress,
        address indexed vaultTokenAddress
    );
    event LiquidityAdded(
        address indexed user,
        address indexed liqTokenAddress,
        uint256 amount,
        uint256 vaultTokens
    );
    event LiquidityRemoved(
        address indexed user,
        address indexed liqTokenAddress,
        uint256 amount,
        uint256 vaultTokens
    );

    /// @dev Function to create a new vault
    /// @param name The name of the vault token
    /// @param symbol The symbol of the vault token
    /// @param liqTokenAddress The address of the liquidity token
    /// @return The address of the newly created vault token
    function createVault(
        string memory name,
        string memory symbol,
        address liqTokenAddress
    ) external onlyOwner returns (address) {
        VaultToken vaultToken = new VaultToken(name, symbol, address(this));
        Vault storage newVault = vaults[liqTokenAddress];
        newVault.vaultTokenAddress = address(vaultToken);
        vaultAddresses.push(liqTokenAddress); 
        emit VaultCreated(liqTokenAddress, address(vaultToken));
        treasury.notifyVaultCreated(liqTokenAddress, address(vaultToken));
        return address(vaultToken);
    }

    /// @dev Function to add liquidity to a vault
    /// @param liqTokenAddress The address of the liquidity token
    /// @param amount The amount of liquidity to add
    function addLiquidity(
        address liqTokenAddress,
        uint256 amount
    ) external payable nonReentrant {
        Vault storage vault = vaults[liqTokenAddress];
        require(vault.vaultTokenAddress != address(0), "Vault does not exist");

        uint256 vaultTokens;

        if (liqTokenAddress == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount sent");
        }

        if (vault.totalVaultTokens == 0) {
            vaultTokens = amount; 
        } else {
            vaultTokens =
                (amount * 100000) /
                getVaultTokenPrice(liqTokenAddress);
        }

        // handleDeposit(liqTokenAddress, msg.value, 0, amount);
        VaultToken(vault.vaultTokenAddress).mint(msg.sender, vaultTokens);

        vault.totalBalance += amount;
        vault.totalVaultTokens += vaultTokens;

        userDeposits[liqTokenAddress][msg.sender].initialAmount += amount;
        userDeposits[liqTokenAddress][msg.sender].vaultTokens += vaultTokens;

        emit LiquidityAdded(msg.sender, liqTokenAddress, amount, vaultTokens);
        treasury.notifyLiquidityAdded(msg.sender, liqTokenAddress, amount, vaultTokens);
    }

    /// @dev Function to remove liquidity from a vault
    /// @param liqTokenAddress The address of the liquidity token
    /// @param vaultTokens The amount of vault tokens to remove
    function removeLiquidity(
        address liqTokenAddress,
        uint256 vaultTokens
    ) external nonReentrant {
        Vault storage vault = vaults[liqTokenAddress];
        require(vault.vaultTokenAddress != address(0), "Vault does not exist");
        require(vaultTokens <= vault.totalVaultTokens,"Not enough vault tokens");

        UserDeposit storage userDeposit = userDeposits[liqTokenAddress][msg.sender];
        require(userDeposit.vaultTokens >= vaultTokens, "Not enough user's vault tokens");

        uint256 initialAmount = userDeposit.initialAmount;
        uint256 userVaultTokens = userDeposit.vaultTokens;

        uint256 withdrawShare = (vaultTokens * 100000) / userVaultTokens;
        uint256 amountWithdrawnFromInitial = (initialAmount * withdrawShare) / 100000;
        require(amountWithdrawnFromInitial <= vault.totalBalance,"Not enough liquidity");
        userDeposit.initialAmount -= amountWithdrawnFromInitial;
        userDeposit.vaultTokens -= vaultTokens;

        uint256 currentPrice = getVaultTokenPrice(liqTokenAddress);
        uint256 amountToWithdraw = (vaultTokens * currentPrice) / 100000;

        vault.totalBalance -= amountWithdrawnFromInitial;
        vault.totalVaultTokens -= vaultTokens;

        VaultToken(vault.vaultTokenAddress).burn(msg.sender, vaultTokens);

        treasury.requestPayout(msg.sender, amountToWithdraw, liqTokenAddress);

        emit LiquidityRemoved(
            msg.sender,
            liqTokenAddress,
            amountToWithdraw,
            vaultTokens
        );
        treasury.notifyLiquidityRemoved(
            msg.sender,
            liqTokenAddress,
            amountToWithdraw,
            vaultTokens
        );
    }

    /// @dev Function to get the price of vault tokens
    /// @param liqTokenAddress The address of the liquidity token
    /// @return The price of vault tokens
    function getVaultTokenPrice(
        address liqTokenAddress
    ) public view returns (uint256) {
        Vault storage vault = vaults[liqTokenAddress];
        require(vault.vaultTokenAddress != address(0), "Vault does not exist");

        uint256 treasuryBalance = treasury.getBalance(liqTokenAddress);

        uint256 lpBalance = vault.totalBalance;

        if (lpBalance == 0) {
            return 100000;
        } else {
            return (treasuryBalance * 100000) / vault.totalVaultTokens;
        }
    }

    /// @dev Function to get all vaults
    /// @return An array of all vaults with updated prices
    function getAllVaults() external view returns (VaultWithPrice[] memory) {
        VaultWithPrice[] memory allVaults = new VaultWithPrice[](vaultAddresses.length);
        for (uint256 i = 0; i < vaultAddresses.length; i++) {
            address liqTokenAddress = vaultAddresses[i];
            Vault storage vault = vaults[liqTokenAddress];
            uint256 currentPrice = getVaultTokenPrice(liqTokenAddress);
            allVaults[i] = VaultWithPrice({
                vaultTokenAddress: vault.vaultTokenAddress,
                liqTokenAddress: liqTokenAddress,
                totalBalance: vault.totalBalance,
                totalVaultTokens: vault.totalVaultTokens,
                vaultTokenPrice: currentPrice
            });
        }
        return allVaults;
    }

    /// @dev Function to get a single vault by its liquidity token address
    /// @param liqTokenAddress The address of the liquidity token
    /// @return The vault associated with the given liquidity token address
    function getVault(address liqTokenAddress) external view returns (VaultWithPrice memory) {
        Vault storage vault = vaults[liqTokenAddress];
        require(vault.vaultTokenAddress != address(0), "Vault does not exist");
        uint256 currentPrice = getVaultTokenPrice(liqTokenAddress);
        return VaultWithPrice({
            vaultTokenAddress: vault.vaultTokenAddress,
            liqTokenAddress: liqTokenAddress,
            totalBalance: vault.totalBalance,
            totalVaultTokens: vault.totalVaultTokens,
            vaultTokenPrice: currentPrice
        });
    }

    function entropyCallback(
        uint64 sequence,
        address provider,
        bytes32 randomNumber
    ) internal virtual override {}
}
