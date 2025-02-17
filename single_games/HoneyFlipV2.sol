// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libs/JunkyUrsasGamesLib.sol";


/// @title HoneyFlip
/// @dev Contract for a simple flipping game where players can wager tokens and win based on random entropy.
contract HoneyFlipV2 is JunkyUrsasGamesLib {
    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @dev Constructor to disable initializers, preventing direct initialization of the proxy contract.
    constructor() {
        _disableInitializers();
    }

    /// @notice Starts a new game of HoneyFlip.
    /// @param config Struct containing game configuration such as wager, probability, and count.
    /// @dev Validates the winning probability, stores the game configuration, and notifies the bankroll.
    function playHoneyflip(GameConfig memory config) 
        external 
        payable 
        maxWagerNotExceeded(config, 100 / config.extra) // Ensures wager does not exceed allowed maximum
        nonReentrant // Prevents reentrancy attacks
        whenNotPaused // Ensures the contract is not paused
    {
        playGame(config);
    }
    
    /// @notice Calculates the game logic for HoneyFlip.
    /// @param config The game configuration.
    /// @param randomNumber The random number.
    /// @param flags The flags.
    /// @return The flags.
    function calculateGameLogic(
        GameConfig memory config,
        bytes32 randomNumber,
        Flags memory flags
    ) internal view override returns (Flags memory) {
        require(config.extra < maxProbability, "Invalid probability");
        require(config.extra > minProbability, "Invalid probability");
        for (uint8 i = 0; i < config.count && flags.playedCount < maxIterations; i++) {
            bool won = (uint256(randomNumber) % 100) < config.extra;

            if (won) {
                uint256 payout = calculateIterationPayout(config.wager, config.extra);
                flags.totalPayout += payout;
                flags.wonCount++;
            }
            flags.playedCount++;

            randomNumber >>= 2;
        }

        return flags;
    }

    /// @notice Calculates the potential payout for a game.
    /// @param wager The amount wagered by the player.
    /// @param probability The probability of winning (as a percentage).
    /// @return The calculated payout amount.
    /// @dev Uses the formula `wager * 100 / probability` to determine the payout.
    function calculateIterationPayout(uint256 wager, uint8 probability) internal pure returns (uint256) {
        return wager * 100 / probability;
    }

    /// @notice Sets a new maximum probability for winning.
    /// @param newMaxProbability The new maximum probability.
    /// @dev Only callable by the contract owner.
    function setMaxProbability(uint8 newMaxProbability) external onlyOwner {
        maxProbability = newMaxProbability;
        emit HoneyFlipMaxProbabilitySet(newMaxProbability);
    }

    /// @notice Retrieves the maximum probability for winning.
    /// @return The maximum probability.
    function getMaxProbability() external view returns (uint8) {
        return maxProbability;
    }

    /// @notice Sets a new minimum probability for winning.
    /// @param newMinProbability The new minimum probability.
    /// @dev Only callable by the contract owner.
    function setMinProbability(uint8 newMinProbability) external onlyOwner {
        minProbability = newMinProbability;
        emit HoneyFlipMinProbabilitySet(newMinProbability);
    }

    /// @notice Retrieves the minimum probability for winning.
    /// @return The minimum probability.
    function getMinProbability() external view returns (uint8) {
        return minProbability;
    }
}
