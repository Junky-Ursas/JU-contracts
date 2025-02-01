// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libs/JunkyUrsasGamesLib.sol";

/// @title BlinkoProxy
/// @dev Proxy contract for a Plinko game, implementing three modes: conservative, balanced, and YOLO.
///      Inherits from BaseGameContractProxy and provides functionality for configuring and playing the game.
contract BlinkoV2 is JunkyUrsasGamesLib {
    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @dev Constructor that disables initializers to prevent direct initialization of the proxy contract.
    constructor() {
        _disableInitializers();
    }

    /// @notice Starts a game of Blinko with the given configuration.
    /// @param config Struct containing game configuration, such as wager, count, and mode.
    /// @dev Validates the wager, ensures the contract is not paused, and stores game data. 
    ///      Emits GameStarted event and notifies the bankroll.
    function playBlinko(GameConfig memory config)
        external
        payable
        maxWagerNotExceeded(config, blinkoMultipliers[config.extra][0]) // Ensures wager doesn't exceed the maximum
        nonReentrant // Prevents reentrancy attacks
        whenNotPaused // Ensures the contract is not paused
    {
        playGame(config);
    }

    /// @notice Calculates the game logic for Blinko.
    /// @param config The game configuration.
    /// @param randomNumber The random number.
    /// @param flags The flags.
    /// @return The flags.  
    function calculateGameLogic(
        GameConfig memory config,
        bytes32 randomNumber,
        Flags memory flags
    ) internal view override returns (Flags memory) {
        uint256[13] memory currentTable = blinkoMultipliers[config.extra];
        bytes32 currentRandom = randomNumber; 
        uint256 bitsUsed = 0; 

        for (uint8 i = 0; i < config.count && flags.playedCount < maxIterations; i++) {
            uint256 path = 0;

            // Generate new random number when we've used all bits
            if (bitsUsed + levelsCount > 256) {
                currentRandom = keccak256(abi.encodePacked(currentRandom, block.timestamp));
                bitsUsed = 0;
            }

            // Extract bits for the current game
            for (uint8 level = 0; level < levelsCount; level++) {
                path += (uint256(currentRandom >> bitsUsed) & 1);
                bitsUsed++;
            }

            path = path % holesCount;

            uint256 payout = (config.wager * currentTable[path]) / 100;
            flags.totalPayout += payout;

            if (payout > 0) {
                flags.wonCount++;
            }
            flags.playedCount++;
        }

        return flags;
    }

    /// @notice Sets the multiplier values for a specific game mode.
    /// @param mode The game mode (0 = conservative, 1 = balanced, 2 = YOLO).
    /// @param newMultipliers Array of 13 multiplier values for the specified mode.
    function setMultipliers(uint8 mode, uint256[13] memory newMultipliers) external onlyOwner {
        require(mode < 3, "Invalid mode"); // Ensure mode is valid
        blinkoMultipliers[mode] = newMultipliers;
        emit BlinkoMultipliersSet(mode, newMultipliers);
    }

    /// @notice Gets the multiplier values for a specific game mode.
    /// @param mode The game mode (0 = conservative, 1 = balanced, 2 = YOLO).
    /// @return An array of 13 multiplier values for the specified mode.
    function getMultipliers(uint8 mode) external view returns (uint256[13] memory) {
        require(mode < 3, "Invalid mode"); // Ensure mode is valid
        return blinkoMultipliers[mode];
    }

    /// @notice Sets the number of levels in the game.
    /// @param newLevelsCount The number of levels (must be greater than 0).
    function setLevelsCount(uint8 newLevelsCount) external onlyOwner {
        require(newLevelsCount > 0, "Invalid levels count");
        levelsCount = newLevelsCount;
        emit BlinkoLevelsCountSet(newLevelsCount);
    }

    /// @notice Gets the number of levels in the game.
    /// @return The number of levels.
    function getLevelsCount() external view returns (uint8) {
        return levelsCount;
    }

    /// @notice Sets the number of holes in the game.
    /// @param newHolesCount The number of holes (must be greater than 0).
    function setHolesCount(uint8 newHolesCount) external onlyOwner {
        require(newHolesCount > 0, "Invalid holes count");
        holesCount = newHolesCount;
        emit BlinkoHolesCountSet(newHolesCount);
    }

    /// @notice Gets the number of holes in the game.
    /// @return The number of holes.
    function getHolesCount() external view returns (uint8) {
        return holesCount;
    }
}