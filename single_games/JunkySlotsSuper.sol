// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libs/JunkyUrsasGamesLib.sol";

contract JunkySlotsSuper is JunkyUrsasGamesLib {

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Launching the game. 
     */
    function playJunkySlotsSuper(GameConfig memory config)
        external
        payable
        nonReentrant
        maxWagerNotExceeded(config, junkySlotsSuperMultipliers[0])
        whenNotPaused
    {
        playGame(config);
    }

    /// @notice Calculates the game logic for JunkySlotsSuper.
    /// @param config The game configuration.
    /// @param randomNumber The random number.
    /// @param flags The flags.
    /// @return The flags.
    function calculateGameLogic(
        GameConfig memory config,
        bytes32 randomNumber,
        Flags memory flags
    ) internal view override returns (Flags memory) {
        bytes32 currentRandom = randomNumber; // Current random number
        uint256 bitsUsed = 0; // Number of bits used

        for (uint8 i = 0; flags.playedCount < config.count && flags.playedCount < maxIterations; i++) {
            // If bits are used up, generate a new random number using hashing
            if (bitsUsed + 54 > 256) {
                currentRandom = keccak256(abi.encodePacked(currentRandom, block.timestamp));
                bitsUsed = 0;
            }

            // Get the payout for the current spin
            (uint256 baseWin, bytes32 rndNext) = getSpinWin(config.wager, currentRandom >> bitsUsed);
            bitsUsed += 24; // Used 24 bits for getSpinWin

            // Apply special symbols
            uint256 spinPayout = applySpecialSymbols(baseWin, i, junkySlotsSuperSpecialConfig, rndNext >> bitsUsed, config);

            bitsUsed += 30; // Used 30 bits for applySpecialSymbols

            flags.totalPayout += spinPayout;
            if (spinPayout > 0) {
                flags.wonCount++;
            }
            flags.playedCount++;
        }

        return flags;
    }

    /**
     * @dev Logic for special symbols (wild, bonus, dead). 
     *      Different parts of randomNumber (mod 1000, /7 %1000, etc.) can be read 
     *      to determine which ones are triggered. 
     *      We limit specialSymbolsPerSpinLimit as in the code.
     */
    function applySpecialSymbols(
        uint256 baseWin,
        uint8 spinIndex,
        SlotsSpecialConfig memory cfg,
        bytes32 rnd,
        GameConfig memory config
    ) internal pure returns (uint256) {
        require(spinIndex < maxIterations, "Invalid spin index");
        // Similar to modifiers: dead increases over time, wild/bonus decreases. 
        uint256 deadModifier = 1000 + spinIndex * 2;    // 100% + 0.2% per spin

        uint256 goodSymbolModifier = 1000 - spinIndex * 2; // 100% - 0.2% per spin

        uint256 spinPayout = baseWin;
        uint8 usedSpecials = 0;


        // Check Dead
        if (usedSpecials < cfg.specialSymbolsPerSpinLimit && config.extra == 1) {
            if (uint256(rnd) % 1000 < (cfg.deadSymbolProbability * deadModifier / 1000)) {
                spinPayout = spinPayout * cfg.deadMultiplier;
                usedSpecials++;
            }
        }

        // Check Wild
        if (usedSpecials < cfg.specialSymbolsPerSpinLimit && config.extra == 1) {
            if (uint256(rnd >> 10) % 1000 < (cfg.wildSymbolProbability * goodSymbolModifier / 1000)) {
                spinPayout = spinPayout * cfg.wildMultiplier;
                usedSpecials++;
            }
        }

        // Check Bonus
        if (usedSpecials < cfg.specialSymbolsPerSpinLimit && config.extra == 1) {
            if (uint256(rnd >> 20) % 1000 < (cfg.bonusSymbolProbability * goodSymbolModifier / 1000)) {
                spinPayout = spinPayout + config.wager; 
                usedSpecials++;
            }
        }

        return spinPayout;
    }

    /**
     * @dev Multiplier for 3 symbols.
     */
    function getSymbolMultiplier(SymbolType s1, SymbolType s2, SymbolType s3) internal view returns (uint256) {
        // Three matches
        if (s1 == s2 && s2 == s3) {
            if (s1 == SymbolType.Symbol0) return junkySlotsSuperMultipliers[0];
            if (s1 == SymbolType.Symbol1) return junkySlotsSuperMultipliers[1];
            if (s1 == SymbolType.Symbol2) return junkySlotsSuperMultipliers[2];
            if (s1 == SymbolType.Symbol3) return junkySlotsSuperMultipliers[3];
            if (s1 == SymbolType.Symbol4) return junkySlotsSuperMultipliers[4];
            if (s1 == SymbolType.Symbol5) return junkySlotsSuperMultipliers[5];
            if (s1 == SymbolType.Symbol6) return junkySlotsSuperMultipliers[6];
            if (s1 == SymbolType.Symbol7) return junkySlotsSuperMultipliers[7];
        }
        // Double matches
        if (s1 == s2 || s2 == s3) {
            SymbolType pairSymbol = (s1 == s2) ? s1 : s2;
            if (pairSymbol == SymbolType.Symbol0) return junkySlotsSuperMultipliers[8];
            if (pairSymbol == SymbolType.Symbol1) return junkySlotsSuperMultipliers[9];
            if (pairSymbol == SymbolType.Symbol2) return junkySlotsSuperMultipliers[10];
            if (pairSymbol == SymbolType.Symbol3) return junkySlotsSuperMultipliers[11];
            if (pairSymbol == SymbolType.Symbol4) return junkySlotsSuperMultipliers[12];
            if (pairSymbol == SymbolType.Symbol5) return junkySlotsSuperMultipliers[13];
            if (pairSymbol == SymbolType.Symbol6) return junkySlotsSuperMultipliers[14];
            if (pairSymbol == SymbolType.Symbol7) return junkySlotsSuperMultipliers[15];
        }
        // Special combinations
        if (s1 == SymbolType.Symbol0 && s3 == SymbolType.Symbol0) return junkySlotsSuperMultipliers[16];
        if (s2 == SymbolType.Symbol0) return junkySlotsSuperMultipliers[17];
        return 0;
    }

    function getReelSymbols(uint8 reelIndex, uint8 symbolIndex) external view returns (uint16) {
        if (reelIndex == 1) return junkySlotsSuperReels[0][symbolIndex];
        if (reelIndex == 2) return junkySlotsSuperReels[1][symbolIndex];
        if (reelIndex == 3) return junkySlotsSuperReels[2][symbolIndex];

        revert("Invalid reel index");
    }

    /**
     * @dev Get base win (without special symbols).
     */
    function getSpinWin(uint256 wager, bytes32 rnd) internal view returns (uint256 spinWin, bytes32 rndNext) {
        // Indices on the reels
        uint256 idx1 = uint256(rnd) % 16;
        uint256 idx2 = uint256(rnd >> 8) % 16;
        uint256 idx3 = uint256(rnd >> 16) % 16;

        SymbolType s1 = SymbolType(this.getReelSymbols(1, uint8(idx1)));
        SymbolType s2 = SymbolType(this.getReelSymbols(2, uint8(idx2))); 
        SymbolType s3 = SymbolType(this.getReelSymbols(3, uint8(idx3)));

        uint256 mult = getSymbolMultiplier(s1, s2, s3);
        spinWin = wager * mult / 100;
        rndNext = rnd >> 24;
    }

    function setReels(uint16[16][3] memory newReels) external onlyOwner {
        junkySlotsSuperReels = newReels;
        emit JunkySlotsSuperReelsSet(newReels);
    }

    function getReels() external view returns (uint16[16][3] memory) {
        return junkySlotsSuperReels;
    }

    function setMultipliers(uint16[18] memory newMultipliers) external onlyOwner {
        junkySlotsSuperMultipliers = newMultipliers;
        emit JunkySlotsSuperMultipliersSet(newMultipliers);
    }

    function getMultipliers() external view returns (uint16[18] memory) {
        return junkySlotsSuperMultipliers;
    }

    /**
     * @dev Setter for specialConfig.
     */
    function setSpecialConfig(SlotsSpecialConfig memory newConfig) external onlyOwner {
        // Check reasonable limits
        require(newConfig.wildSymbolProbability <= 100 && newConfig.wildSymbolProbability >= 0, "Wild prob too high");
        require(newConfig.bonusSymbolProbability <= 100 && newConfig.bonusSymbolProbability >= 0, "Bonus prob too high");
        require(newConfig.deadSymbolProbability <= 100 && newConfig.deadSymbolProbability >= 0, "Dead prob too high");
        require(newConfig.specialSymbolsPerSpinLimit <= 3 && newConfig.specialSymbolsPerSpinLimit >= 0, "Too many special symbols");
        require(newConfig.wildMultiplier <= 100 && newConfig.wildMultiplier >= 0, "Wild multiplier too high");
        require(newConfig.deadMultiplier <= 100 && newConfig.deadMultiplier >= 0, "Dead multiplier too high");

        junkySlotsSuperSpecialConfig = newConfig;
        emit JunkySlotsSuperSpecialConfigSet(newConfig);
    }

    function getSpecialConfig() external view returns (SlotsSpecialConfig memory) {
        return junkySlotsSuperSpecialConfig;
    }
}