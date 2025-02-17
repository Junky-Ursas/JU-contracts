// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libs/JunkyUrsasGamesLib.sol";

/// @title JunkySlots
/// @dev Contract for a slot machine game where players wager tokens and win based on random entropy.
contract JunkySlotsV2 is JunkyUrsasGamesLib {

    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @dev Constructor disables initializers to prevent direct initialization of the proxy contract.
    constructor() {
        _disableInitializers();
    }

    /// @notice Starts a new game of JunkySlots.
    /// @param config The game configuration, including wager, count, and extra parameters.
    /// @dev Validates and processes the game start request, emitting an event and notifying the bankroll.
    function playJunkySlotsV2(GameConfig memory config)
        external
        payable
        maxWagerNotExceeded(config, junkySlotsV2SpecialMultipliers[0] / 2) // Ensures wager is within the maximum limit
        nonReentrant // Prevents reentrancy attacks
        whenNotPaused // Ensures the contract is not paused
    {
        playGame(config);
    }

    /// @notice Calculates the game logic for JunkySlotsV2.
    /// @param config The game configuration.
    /// @param randomNumber The random number.
    /// @param flags The flags.
    /// @return The flags.
    function calculateGameLogic(
        GameConfig memory config,
        bytes32 randomNumber,
        Flags memory flags
    ) internal view override returns (Flags memory) {
        // Process each iteration of the slot spins
        for (uint8 i = 0; i < config.count && flags.playedCount < maxIterations; i++) {
            // Generate slot symbols from the random number
            Symbols memory symbols = Symbols(
                uint8(uint256(randomNumber) % 7),
                uint8((uint256(randomNumber) / 7) % 7),
                uint8((uint256(randomNumber) / 49) % 7)
            );

            // Determine multiplier based on the slot symbols
            uint16 currentMultiplier = getMultiplier(symbols);

            // Apply special multiplier conditions
            if (flags.previousMultiplier == 6 && currentMultiplier == 9) {
                currentMultiplier = junkySlotsV2SpecialMultipliers[0];
            } else if (flags.previousMultiplier == 9 && currentMultiplier == 9) {
                currentMultiplier = junkySlotsV2SpecialMultipliers[1];
            } else if (flags.previousMultiplier == 3 && currentMultiplier == 6) {
                currentMultiplier = junkySlotsV2SpecialMultipliers[2];
            }

            // Update previous multiplier for the next iteration
            flags.previousMultiplier = currentMultiplier;

            // Update total payout and increment the count of played games
            flags.totalPayout += config.wager * currentMultiplier;
            flags.playedCount++;

            // Shift the random number for the next iteration
            randomNumber >>= 3;
        }

        return flags;
    }

    /// @notice Determines the multiplier based on the slot symbols.
    /// @param symbols The slot symbols generated during the game.
    /// @return The multiplier for the payout.
    /// @dev Uses specific symbol combinations to determine the multiplier.
    function getMultiplier(Symbols memory symbols) internal view returns (uint16) {
        if (symbols.symbol1 == 0 && symbols.symbol2 == 0 && symbols.symbol3 == 0) // Triple 0
            return junkySlotsV2Multipliers[0];
        if (symbols.symbol1 == 1 && symbols.symbol2 == 1 && symbols.symbol3 == 0) // Double 1, Single 0
            return junkySlotsV2Multipliers[1];
        if (symbols.symbol1 == 1 && symbols.symbol2 == 1 && symbols.symbol3 == 1) // Triple 1
            return junkySlotsV2Multipliers[2];
        if (symbols.symbol1 == 2 && symbols.symbol2 == 2) // Double 2
            return junkySlotsV2Multipliers[3];
        if (symbols.symbol1 == 3 && symbols.symbol2 == 3) // Double 3
            return junkySlotsV2Multipliers[4];
        if (symbols.symbol1 == 4 && symbols.symbol2 == 4) // Double 4
            return junkySlotsV2Multipliers[5];
        if (symbols.symbol1 == 5 && symbols.symbol2 == 5) // Double 5
            return junkySlotsV2Multipliers[6];
        if (symbols.symbol1 == 6 && symbols.symbol2 == 6) // Double 6
            return junkySlotsV2Multipliers[7];
        if (symbols.symbol1 == 0 && symbols.symbol2 != 0 && symbols.symbol3 == 0) // Sandwich 0
            return junkySlotsV2Multipliers[8];
        if (symbols.symbol1 != 0 && symbols.symbol2 == 0 && symbols.symbol3 == 0) // Leading 0s
            return junkySlotsV2Multipliers[9];
        if (symbols.symbol1 == 1 && symbols.symbol2 != 1 && symbols.symbol3 == 1) // Sandwich 1
            return junkySlotsV2Multipliers[10];
        if (symbols.symbol1 != 1 && symbols.symbol2 == 1 && symbols.symbol3 == 1) // Leading 1s
            return junkySlotsV2Multipliers[11];
        return junkySlotsV2Multipliers[12]; // Default multiplier
    }

    /// @notice Updates the multipliers for the game.
    /// @param newMultipliers Array of new multipliers.
    /// @dev Only callable by the owner.
    function setMultipliers(uint16[13] memory newMultipliers) external onlyOwner {
        junkySlotsV2Multipliers = newMultipliers;
        emit JunkySlotsV2MultipliersSet(newMultipliers);
    }

    /// @notice Gets the current multipliers for the game.
    /// @return An array of multipliers.
    function getMultipliers() external view returns (uint16[13] memory) {
        return junkySlotsV2Multipliers;
    }

    /// @notice Updates the special multipliers for the game.
    /// @param newSpecialMultipliers Array of new special multipliers.
    /// @dev Only callable by the owner.
    function setSpecialMultipliers(uint16[3] memory newSpecialMultipliers) external onlyOwner {
        junkySlotsV2SpecialMultipliers = newSpecialMultipliers;
        emit JunkySlotsV2SpecialMultipliersSet(newSpecialMultipliers);
    }

    /// @notice Gets the current special multipliers for the game.
    /// @return An array of special multipliers.
    function getSpecialMultipliers() external view returns (uint16[3] memory) {
        return junkySlotsV2SpecialMultipliers;
    }

}
