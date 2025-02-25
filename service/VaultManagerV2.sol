// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libs/JunkyUrsasEventsLib.sol";
import "./VaultTokenV2.sol";
import "./Bankroll.sol";

import "hardhat/console.sol";

/// @title VaultManager - Manages Vaults and their liquidity
contract VaultManagerV2 is JunkyUrsasEventsLib {
    uint256 private constant PRECISION = 1e18; // Use 1e18 for higher precision
    Bankroll internal bankroll;       // Bankroll contract for handling deposits and payouts

    /// @dev Struct for user information related to a specific liquidity token
    struct UserInfo {
        UserDeposit deposit;
        UserStats stats;
        mapping(address stakingContract => StakingInfo) stakingInfos;
    }

    /// @dev Mapping for staking contracts
    mapping(address stakingContractAddress => bool) internal stakingContracts;
    /// @dev Mapping for vaults
    mapping(address liqTokenAddress => Vault) private vaults; 
    /// @dev Mapping for user 
    mapping(address liqTokenAddress => mapping(address userAddress => UserInfo)) internal userInfo; 
    /// @dev Mapping for vault addresses
    mapping(address vaultTokenAddress => bool) internal isVaultTokenExists;
    /// @dev Array for liquidity token addresses
    address[] internal liqTokenAddresses; 

    /// @dev Function to initialize the contract
    /// @param bankrollAddress The address of the bankroll contract
    function initialize(address bankrollAddress) initializer public {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        bankroll = Bankroll(bankrollAddress);
    }

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
        VaultTokenV2 vaultToken = new VaultTokenV2(name, symbol, address(this), liqTokenAddress, address(this));
        Vault storage newVault = vaults[liqTokenAddress];
        isVaultTokenExists[address(vaultToken)] = true;
        newVault.vaultTokenAddress = address(vaultToken);
        liqTokenAddresses.push(liqTokenAddress); 
        emit VaultCreated(liqTokenAddress, address(vaultToken));
        bankroll.notifyVaultCreated(liqTokenAddress, address(vaultToken));
        return address(vaultToken);
    }

    /// @dev Function to add liquidity to a vault
    function addLiquidity(
        address liqTokenAddress,
        uint256 amount,
        uint256 minVaultTokens // New parameter for slippage protection
    ) external payable nonReentrant {
        Vault storage vault = vaults[liqTokenAddress];
        require(vault.vaultTokenAddress != address(0), "Vault does not exist");
        UserInfo storage user = userInfo[liqTokenAddress][msg.sender];
        validateAddLiquidityInputs(liqTokenAddress, amount);

        uint256 vaultTokens = calculateVaultTokens(liqTokenAddress, amount, vault.totalVaultTokens);

        // Slippage protection: Ensure the user receives at least `minVaultTokens`
        require(vaultTokens >= minVaultTokens, "Slippage too high: Received fewer tokens than expected");

        handleDeposit(msg.value, amount, msg.sender, liqTokenAddress);
        mintVaultTokens(liqTokenAddress, user, vaultTokens);
        updateVaultAndUserData(liqTokenAddress, user, amount, vaultTokens);

        emit LiquidityAdded(msg.sender, liqTokenAddress, amount, vaultTokens);
        bankroll.notifyLiquidityAdded(msg.sender, liqTokenAddress, amount, vaultTokens);
    }

    /// @dev Validates inputs for adding liquidity
    function validateAddLiquidityInputs(address liqTokenAddress, uint256 amount) internal view {
        if (liqTokenAddress == address(0)) {
            require(msg.value >= amount, "Incorrect ETH amount sent");
        }
    }

    /// @dev Calculates the number of vault tokens to mint
    function calculateVaultTokens(
        address liqTokenAddress,
        uint256 amount,
        uint256 totalVaultTokens
    ) internal view returns (uint256) {
        if (totalVaultTokens == 0) {
            return amount;
        } else {
            return (amount * PRECISION) / getVaultTokenPrice(liqTokenAddress);
        }
    }

    /// @dev Mints vault tokens to the user
    function mintVaultTokens(address liqTokenAddress, UserInfo storage user, uint256 vaultTokens) internal {
        VaultTokenV2(vaults[liqTokenAddress].vaultTokenAddress).mint(msg.sender, vaultTokens);
        user.deposit.vaultTokens += vaultTokens;
    }

    /// @dev Updates the vault and user data after adding liquidity
    function updateVaultAndUserData(
        address liqTokenAddress,
        UserInfo storage user,
        uint256 amount,
        uint256 vaultTokens
    ) internal {
        Vault storage vault = vaults[liqTokenAddress];
        vault.totalBalance += amount;
        vault.totalVaultTokens += vaultTokens;
        user.stats.totalDeposited += amount;
        user.stats.lastDepositTimestamp = block.timestamp;

        updateAverageExchangeRate(user.deposit, liqTokenAddress, amount, vaultTokens);
    }

    /// @dev Updates the average exchange rate for the user
    function updateAverageExchangeRate(
        UserDeposit storage userDeposit,
        address liqTokenAddress,
        uint256 amount,
        uint256 vaultTokens
    ) internal {
        if (userDeposit.vaultTokens == vaultTokens) {
            // First deposit
            userDeposit.avgExchangeRate = getVaultTokenPrice(liqTokenAddress);
        } else {
            // Subsequent deposits
            uint256 newAmount = amount;
            uint256 prevAmount = (userDeposit.vaultTokens * userDeposit.avgExchangeRate) / PRECISION;
            uint256 totalAmount = prevAmount + newAmount;
            uint256 totalTokens = userDeposit.vaultTokens;
            userDeposit.avgExchangeRate = (totalAmount * PRECISION) / totalTokens;
        }
    }


        /// @dev Function to remove liquidity from a vault
    function removeLiquidity(
        address liqTokenAddress,
        uint256 vaultTokens
    ) external nonReentrant {
        Vault storage vault = vaults[liqTokenAddress];
        require(vault.vaultTokenAddress != address(0), "Vault does not exist");
        require(vaultTokens <= vault.totalVaultTokens, "Not enough vault tokens");

        UserInfo storage user = userInfo[liqTokenAddress][msg.sender];

        validateRemoveLiquidityInputs(vault, user.deposit, vaultTokens);

        uint256 amountWithdrawnFromInitial = calculateWithdrawalAmount(liqTokenAddress, user.deposit, vaultTokens);
        uint256 currentPrice = getVaultTokenPrice(liqTokenAddress);
        uint256 amountToWithdraw = (vaultTokens * currentPrice) / PRECISION;

        updateVaultAndUserDataOnWithdrawal(liqTokenAddress, user, vaultTokens, amountWithdrawnFromInitial);

        VaultTokenV2(vault.vaultTokenAddress).burn(msg.sender, vaultTokens);

        bankroll.requestPayoutFromBankroll(msg.sender, amountToWithdraw, liqTokenAddress);

        emit LiquidityRemoved(msg.sender, liqTokenAddress, amountToWithdraw, vaultTokens);
        bankroll.notifyLiquidityRemoved(msg.sender, liqTokenAddress, amountToWithdraw, vaultTokens);
    }

    /// @dev Validates inputs for removing liquidity
    function validateRemoveLiquidityInputs(
        Vault storage vault,
        UserDeposit storage userDeposit,
        uint256 vaultTokens
    ) internal view {
        require(userDeposit.vaultTokens >= vaultTokens, "Not enough user's vault tokens");
        require(VaultTokenV2(vault.vaultTokenAddress).balanceOf(msg.sender) >= vaultTokens, "You don't have enough vault tokens");
    }

    /// @dev Calculates the amount withdrawn from the initial deposit
    function calculateWithdrawalAmount(
        address liqTokenAddress,
        UserDeposit storage userDeposit,
        uint256 vaultTokens
    ) internal view returns (uint256) {
        Vault storage vault = vaults[liqTokenAddress];
        uint256 initialAmount = (userDeposit.avgExchangeRate * userDeposit.vaultTokens) / PRECISION;
        uint256 withdrawShare = (vaultTokens * PRECISION) / userDeposit.vaultTokens;
        uint256 amountWithdrawn = (initialAmount * withdrawShare) / PRECISION;
        require(amountWithdrawn <= vault.totalBalance, "Not enough liquidity");
        return amountWithdrawn;
    }

    /// @dev Updates the vault and user data upon withdrawal
    function updateVaultAndUserDataOnWithdrawal(
        address liqTokenAddress,
        UserInfo storage user,
        uint256 vaultTokens,
        uint256 amountWithdrawn
    ) internal {
        vaults[liqTokenAddress].totalBalance -= amountWithdrawn;
        vaults[liqTokenAddress].totalVaultTokens -= vaultTokens;
        user.deposit.vaultTokens -= vaultTokens;
        user.stats.totalWithdrawn += amountWithdrawn;
    }

    /// @dev Handles deposits of wagers in either Ether or ERC20 tokens.
    function handleDeposit(uint256 msgValue,  uint256 amount, address msgSender, address token) 
        internal returns (bool)
    {
        // Handle deposits of wagers in either Ether or ERC20 tokens
        if (token == address(0)) {
            // If the token is Ether
            require(msgValue >= amount, "Provided ETH amount too low");
            bankroll.depositETH{value: amount}(msgSender, amount);
        } else {
            // If the token is an ERC20 token
            IERC20 tokenContract = IERC20(token);
            uint256 allowance = tokenContract.allowance(msgSender, address(bankroll));
            require(allowance >= amount, "Allowance too low");
            bankroll.depositERC20(token, msgSender, amount);
        }

        return true;
    }

    /// @dev Function to handle vault token transfer
    function handleVaultTokenTransfer(
        address from,
        address to,
        uint256 vaultTokens,
        address liqTokenAddress
    ) external {
        // Ignore transfers in/out vault, as they are handled in addLiquidity/removeLiquidity
        if (to == address(this) || from == address(this)) {
            return;
        }
        require(isVaultTokenExists[msg.sender], "Caller is not a valid vault token");

        if (stakingContracts[to]) {
            handleStaking(from, to, liqTokenAddress, vaultTokens);
        } else if (stakingContracts[from]) {
            handleUnstaking(from, to, liqTokenAddress, vaultTokens);
        } else {
            handleUserTransfer(from, to, liqTokenAddress, vaultTokens);
        }
    }

    /// @dev Handles staking logic
    function handleStaking(
        address from,
        address to,
        address liqTokenAddress,
        uint256 vaultTokens
    ) internal {
        UserInfo storage user = userInfo[liqTokenAddress][from];
        StakingInfo storage stakingInfo = user.stakingInfos[to];
        stakingInfo.stakedAmount += vaultTokens;
        stakingInfo.stakingContract = to;

        uint256 stakedAmount = (vaultTokens * user.deposit.avgExchangeRate) / PRECISION;
        emit VaultTokenStaked(from, to, liqTokenAddress, vaultTokens, stakedAmount);
    }

    /// @dev Handles unstaking logic
    function handleUnstaking(
        address from,
        address to,
        address liqTokenAddress,
        uint256 vaultTokens
    ) internal {
        StakingInfo storage stakingInfo = userInfo[liqTokenAddress][from].stakingInfos[to];
        require(stakingInfo.stakedAmount >= vaultTokens, "Staked amount insufficient");
        stakingInfo.stakedAmount -= vaultTokens;
        emit VaultTokenUnstaked(from, to, liqTokenAddress, vaultTokens);
    }

    /// @dev Handles user-to-user transfer logic
    function handleUserTransfer(
        address from,
        address to,
        address liqTokenAddress,
        uint256 vaultTokens
    ) internal {
        UserInfo storage fromUser = userInfo[liqTokenAddress][from];
        UserInfo storage toUser = userInfo[liqTokenAddress][to];
        uint256 currentPrice = getVaultTokenPrice(liqTokenAddress);

        fromUser.deposit.vaultTokens -= vaultTokens;
        toUser.deposit.vaultTokens += vaultTokens;

        updateRecipientExchangeRate(toUser.deposit, vaultTokens, currentPrice);

        emit VaultTokenTransferred(from, to, liqTokenAddress, vaultTokens, (vaultTokens * currentPrice) / PRECISION);
    }

    /// @dev Updates the average exchange rate for the recipient
    function updateRecipientExchangeRate(
        UserDeposit storage toDeposit,
        uint256 vaultTokens,
        uint256 currentPrice
    ) internal {
        if (toDeposit.vaultTokens == vaultTokens) {
            // First tokens for the receiver
            toDeposit.avgExchangeRate = currentPrice;
        } else {
            // Update the average exchange rate for existing tokens
            uint256 existingValue = ((toDeposit.vaultTokens - vaultTokens) * toDeposit.avgExchangeRate) / PRECISION;
            uint256 newValue = (vaultTokens * currentPrice) / PRECISION;
            toDeposit.avgExchangeRate = ((existingValue + newValue) * PRECISION) / toDeposit.vaultTokens;
        }
    }

    /// @dev Function to get the price of vault tokens
    function getVaultTokenPrice(
        address liqTokenAddress
    ) public view returns (uint256) {
        Vault storage vault = vaults[liqTokenAddress];
        require(vault.vaultTokenAddress != address(0), "Vault does not exist");
    
        uint256 bankrollBalance = bankroll.getBalance(liqTokenAddress);
        uint256 totalVaultTokens = vault.totalVaultTokens;
    
        if (totalVaultTokens == 0) {
            return PRECISION; // Initial price
        }
    
        if (bankrollBalance == 0) {
            return 1; // Avoid division by zero (for real)
        }
        require(bankrollBalance > 0, "Bankroll balance is zero");
        return (bankrollBalance * PRECISION) / totalVaultTokens;
    }

    /// @dev Function to get all vaults
    /// @return An array of all vaults with updated prices
    function getAllVaults() external view returns (VaultWithPrice[] memory) {
        VaultWithPrice[] memory allVaults = new VaultWithPrice[](liqTokenAddresses.length);
        for (uint256 i = 0; i < liqTokenAddresses.length; i++) {
            address liqTokenAddress = liqTokenAddresses[i];
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

    /// @dev Function to add staking contract
    /// @param stakingContract The address of the staking contract
    function addStakingContract(address stakingContract) external onlyOwner {
        stakingContracts[stakingContract] = true;
        emit StakingContractAdded(stakingContract);
    }

    /// @dev Function to remove staking contract
    /// @param stakingContract The address of the staking contract
    function removeStakingContract(address stakingContract) external onlyOwner {
        stakingContracts[stakingContract] = false;
        emit StakingContractRemoved(stakingContract);
    }

    function getStakingInfo(address liqToken, address user, address stakingContract) external view returns (StakingInfo memory) {
        return userInfo[liqToken][user].stakingInfos[stakingContract];
    }

    function getUserDeposit(address liqToken, address user) external view returns (UserDeposit memory) {
        return userInfo[liqToken][user].deposit;
    }

    function getUserStats(address liqToken, address user) external view returns (UserStats memory) {
        return userInfo[liqToken][user].stats;
    }

    function getBankroll() external view returns (address) {
        return address(bankroll);
    }
}
