// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./entropy/IEntropyConsumer.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./TreasuryContract.sol";
import "./entropy/IEntropy.sol";


/// @title BaseGameContract
/// @notice Abstract contract implementing core functionality for games using entropy and treasury management
/// @dev Provides base functionality for game contracts including entropy handling and treasury interactions
abstract contract BaseGameContractProxy is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, IEntropyConsumer {

    /// @dev Constructor to initialize the HoneyFlip contract.
    /// @param treasuryAddress The address of the treasury contract
    /// @param entropyAddress The address of the entropy contract
    /// @param entropyProviderAddress The address of the entropy provider
    function initialize(address treasuryAddress, address entropyAddress, address entropyProviderAddress) 
    initializer public
    {
        // Initialize the contract state variables
        __Ownable_init(msg.sender); // Set the owner of the contract
        __ReentrancyGuard_init(); // Initialize the reentrancy guard
        treasury = TreasuryContractProxy(treasuryAddress); // Set the treasury contract
        entropy = IEntropy(entropyAddress); // Set the entropy contract
        entropyProvider = entropyProviderAddress; // Set the entropy provider
        houseEdge = 3; // Set the house edge percentage
        minAmount = 1e16; // Set the minimum bet amount
    }

    /// @dev Emitted when a game is started.
    event GameStarted(
        uint64 sequenceNumber, 
        address indexed player, 
        uint256 wager, 
        uint8 count, 
        address indexed token,
        bytes32 indexed userRandomNumber
    );

    /// @dev Emitted when a game result is processed.
    event GameResult(
        address indexed player,
        uint256 payout,
        bytes32 indexed randomNumber,
        uint8 wonCount,
        uint8 totalCount,
        address indexed token
    );

    /// @notice Game configuration parameters
    /// @param player Address of the player
    /// @param token Address of the token used for wager (0x0 for ETH)
    /// @param wager Amount wagered by the player
    /// @param userRandomNumber User-provided random number for additional entropy
    /// @param extra Additional game-specific parameter (e.g. winning probability)
    /// @param count Number of game iterations
    struct GameConfig {
        address player;             
        address token;              
        uint256 wager;              
        bytes32 userRandomNumber;   
        uint8 extra;                
        uint8 count;                
    }

    /// @notice Symbols used in games
    struct Symbols {
        uint8 symbol1;
        uint8 symbol2;
        uint8 symbol3;
    }
    
    /// @notice Game state flags and tracking
    struct Flags {
        uint256 totalPayout;
        uint8 wonCount;
        uint8 playedCount;
        bytes32 initialRandomNumber;
        uint256 previousMultiplier;
    }
    
    IEntropy public entropy;                // Entropy contract for randomness
    address public entropyProvider;         // Address of the entropy provider
    TreasuryContractProxy public treasury;       // Treasury contract for handling deposits and payouts
    uint256 public houseEdge;               // House edge percentage
    uint256 public minAmount;           // Minimum bet amount

    mapping(uint64 sequenceNumber => bytes) public games;   // Mapping from sequence number to Game struct

    /// @dev Sets the house edge percentage.
    /// @param newEdge The new house edge percentage
    function setHouseEdge(uint256 newEdge) external onlyOwner {
        houseEdge = newEdge;
    }

    /// @dev Sets the address of the treasury contract.
    /// @param newTreasury The address of the new treasury contract
    function setTreasuryContract(address newTreasury) external onlyOwner {
        treasury = TreasuryContractProxy(newTreasury);
    }

    /// @dev Sets the minimum bet amount.
    /// @param _minAmount The new minimum bet amount
    function setMinAmount(uint256 _minAmount) external onlyOwner {
        minAmount = _minAmount;
    }

    /// @dev Returns the address of the entropy contract.
    /// @return The address of the entropy contract
    function getEntropy() internal view override returns (address) {
        return address(entropy);
    }

    /// @dev Returns the game configuration for a specific sequence number.
    /// @param sequenceNumber The sequence number of the game
    /// @return The game configuration
    function getGame(uint64 sequenceNumber) external view returns (GameConfig memory) {
        return abi.decode(games[sequenceNumber], (GameConfig));
    }

    /// @dev Fallback function to receive Ether.
    receive() external payable {}
}

