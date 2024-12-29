// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";


/// @title BaseGameContract
/// @dev Сontract that implements core functionality for games using entropy and treasury management.
abstract contract JunkyUrsasStructsLib is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    /// @dev Game configuration struct
    struct GameConfig {
        address player; // Address of the player
        address token; // Address of the token used for the wager
        address gameAddress; // Address of the game contract
        bytes32 userRandomNumber; // User-provided random number for additional entropy
        uint256 wager; // Amount wagered by the player
        uint256 timestamp; // Timestamp of the game start
        uint8 extra; // Winning probability (1% to 69%)
        uint8 count; // Number of game iterations
    }

    /// @dev Symbols on the reels
    struct Symbols {
        uint8 symbol1;
        uint8 symbol2;
        uint8 symbol3;
    }

    /// @dev Game flags struct
    struct Flags {
        uint256 totalPayout;
        uint8 wonCount;
        uint8 playedCount;
        bytes32 initialRandomNumber;
        uint256 previousMultiplier;
    }

    /// @dev Speical parameters for JunkySlots V2 (probabilities, multipliers, etc.)
    ///      Can be considered as "contract settings".
    struct SlotsSpecialConfig {
        uint256 wildSymbolProbability;
        uint256 bonusSymbolProbability;
        uint256 deadSymbolProbability;
        uint256 wildMultiplier; // For example 2 = x2
        uint256 deadMultiplier; // For example 0 = all is lost
        uint8 specialSymbolsPerSpinLimit;
    }
    
    /// @dev Symbols on the reels for JunkySlots V2
    enum SymbolType {
        Symbol0,
        Symbol1,
        Symbol2,
        Symbol3,
        Symbol4,
        Symbol5,
        Symbol6,
        Symbol7
    }

    /// @dev Struct for vault 
    struct Vault {
        address vaultTokenAddress;
        uint256 totalBalance;
        uint256 totalVaultTokens;
    }
    
    /// @dev Struct for staking info
    struct StakingInfo {
        uint256 stakedAmount;
        address stakingContract;
    }

    /// @dev Struct for vault with price
    struct VaultWithPrice {
        address vaultTokenAddress;
        address liqTokenAddress;
        uint256 totalBalance;
        uint256 totalVaultTokens;
        uint256 vaultTokenPrice; 
    }

    /// @dev Struct for user deposit
    struct UserDeposit {
        uint256 avgExchangeRate; 
        uint256 vaultTokens;
    }
    /// @dev Struct for user stats
    struct UserStats {
        uint256 totalDeposited;
        uint256 totalWithdrawn;
        uint256 lastDepositTimestamp;
    }
}
