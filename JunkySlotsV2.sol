// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BaseGameContract.sol";

contract BetterJunkySlotsProxy is BaseGameContractProxy {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Symbols on the reels
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

    /// @dev Speical parameters (probabilities, multipliers, etc.)
    ///      Can be considered as "contract settings".
    struct SlotsSpecialConfig {
        uint256 wildSymbolProbability;  
        uint256 bonusSymbolProbability; 
        uint256 deadSymbolProbability;

        uint256 wildMultiplier;         // For example 2 = x2
        uint256 deadMultiplier;         // For example 0 = all is lost
        uint8   specialSymbolsPerSpinLimit; 

        uint8   houseEdge;             // Commission (in %)
    }

    uint8[16][3] public reels;
    // [
    //     [0,1,2,3,4,5,6,7,3,4,5,6,7,7,7,7],
    //     [0,1,2,3,4,5,6,7,2,3,4,5,6,7,7,7],
    //     [0,1,2,3,4,5,6,7,1,2,3,4,5,6,7,7]
    // ];

    /// @dev Stores the current configuration of special symbols. Can be made a setter for changing.
    SlotsSpecialConfig public specialConfig;
    // {
    //     wildSymbolProbability: 20,
    //     bonusSymbolProbability: 5,
    //     deadSymbolProbability: 20,
    //     wildMultiplier: 2,
    //     deadMultiplier: 0,
    //     specialSymbolsPerSpinLimit: 1,
    //     houseEdge: 0
    // };

    /// @dev For storing data between play/Callback
    struct SlotsGameConfig {
        uint8  count;           // Number of spins
        uint256 wager;          // Bet
        address token;          // Token (0 = ETH)
        bytes32 userRandomNumber;
        address player;
        uint8 extra;
    }

    /**
     * @dev Launching the game. 
     */
    function playJunkySlotsV2(GameConfig memory config)
        external
        payable
        nonReentrant
    {
        require(config.count > 0 && config.count < 70, "Invalid spin count");

        uint256 fee = entropy.getFee(entropyProvider);
        require(msg.value >= fee, "Insufficient fee");
        require(config.wager * config.count >= minAmount, "Bet below min");

        if (config.token == address(0)) {
            // Bet in ETH
            require(msg.value > fee, "Bet amount too low");
            uint256 netAmount = msg.value - fee;
            require(netAmount >= config.wager * config.count, "Bet amount too low");
        } else {
            // ERC20
            IERC20 tokenContract = IERC20(config.token);
            uint256 allowance = tokenContract.allowance(msg.sender, address(this));
            require(allowance >= config.wager * config.count, "Allowance too low");
            tokenContract.transferFrom(msg.sender, address(this), config.wager * config.count);
        }

        uint64 sequenceNumber = entropy.requestWithCallback{value: fee}(entropyProvider, config.userRandomNumber);
        
        // Save SlotsGameConfig
        SlotsGameConfig memory slotCfg = SlotsGameConfig({
            count:  uint8(config.count),
            wager:  config.wager,
            token:  config.token,
            userRandomNumber: config.userRandomNumber,
            player: msg.sender,
            extra: config.extra
        });
        games[sequenceNumber] = abi.encode(slotCfg);

        emit GameStarted(sequenceNumber, msg.sender, config.wager, config.count, config.token, config.userRandomNumber);
        treasury.notifyGameStarted(sequenceNumber, msg.sender, config.wager, config.count, config.token);
    }

    /**
     * @dev entropyCallback - here the reels are spinning, 
     *      plus checking Wild/Bonus/Dead (with a limit of specialSymbolsPerSpinLimit).
     */
    function entropyCallback(uint64 sequenceNumber, address, bytes32 randomNumber) internal override {
        SlotsGameConfig memory slotCfg = abi.decode(games[sequenceNumber], (SlotsGameConfig));
        Flags memory flags;
        flags.initialRandomNumber = randomNumber;

        uint256 totalRefund = 0;
        // For each spin
        for (uint8 i = 0; i < slotCfg.count && i < 69; i++) {
            // Calculate the base win
            (uint256 baseWin, bytes32 rndNext) = getSpinWin(slotCfg.wager, randomNumber);
            randomNumber = rndNext;

            // Apply special symbols
            uint256 spinPayout = applySpecialSymbols(baseWin, i, specialConfig, randomNumber, slotCfg);
            // Shift the random number again (to avoid confusion with reel indices)
            randomNumber = randomNumber >> 16;

            // Subtract houseEdge
            spinPayout = (spinPayout * (100 - specialConfig.houseEdge)) / 100;

            totalRefund += spinPayout;
            if (spinPayout > 0) {
                flags.wonCount++;
            }
            flags.playedCount++;
        }

        // Calculate unplayed spins
        uint256 unplayed = slotCfg.wager * (slotCfg.count - flags.playedCount);
        uint256 finalRefund = totalRefund + unplayed;

        if (finalRefund > 0) {
            treasury.requestPayout(slotCfg.player, finalRefund, slotCfg.token);
        }

        // Deposit in treasury
        uint256 totalWager = slotCfg.wager * slotCfg.count;
        if (slotCfg.token == address(0)) {
            treasury.deposit{value: totalWager}(totalWager);
        } else {
            IERC20 tokenContract = IERC20(slotCfg.token);
            tokenContract.approve(address(treasury), totalWager);
            treasury.transferFrom(slotCfg.token, address(this), address(treasury), totalWager);
        }

        emit GameResult(
            slotCfg.player,
            finalRefund,
            flags.initialRandomNumber,
            flags.wonCount,
            flags.playedCount,
            slotCfg.token
        );

        treasury.notifyGameResult(
            sequenceNumber,
            finalRefund,
            flags.initialRandomNumber,
            flags.wonCount,
            flags.playedCount,
            slotCfg.extra
        );
    }

    /**
     * @dev Логика спецсимволов (wild, bonus, dead). 
     *      Можно читать разные части randomNumber (mod 1000, /7 %1000 и т.п.), 
     *      чтобы определить, какие сработали. 
     *      Ограничиваем specialSymbolsPerSpinLimit, как в коде.
     */
    function applySpecialSymbols(
        uint256 baseWin,
        uint8 spinIndex,
        SlotsSpecialConfig memory cfg,
        bytes32 rnd,
        SlotsGameConfig memory slotCfg
    ) internal pure returns (uint256) {
        require(spinIndex < 70, "Invalid spin index");
        // Similar to modifiers: dead increases over time, wild/bonus decreases. 
        uint256 deadModifier = 1000 + spinIndex * 2;    // 100% + 0.2% per spin
        uint256 goodSymbolModifier = 1000 - spinIndex * 2; // 100% - 0.2% per spin

        uint256 spinPayout = baseWin;
        uint8 usedSpecials = 0;


        // Check Dead
        if (usedSpecials < cfg.specialSymbolsPerSpinLimit && slotCfg.extra == 1) {
            if (uint256(rnd) % 1000 < (cfg.deadSymbolProbability * deadModifier / 1000)) {
                spinPayout = spinPayout * cfg.deadMultiplier;
                usedSpecials++;
            }
        }

        // Check Wild
        if (usedSpecials < cfg.specialSymbolsPerSpinLimit && slotCfg.extra == 1) {
            if (uint256(rnd >> 10) % 1000 < (cfg.wildSymbolProbability * goodSymbolModifier / 1000)) {
                spinPayout = spinPayout * cfg.wildMultiplier;
                usedSpecials++;
            }
        }

        // Check Bonus
        if (usedSpecials < cfg.specialSymbolsPerSpinLimit && slotCfg.extra == 1) {
            if (uint256(rnd >> 20) % 1000 < (cfg.bonusSymbolProbability * goodSymbolModifier / 1000)) {
                spinPayout = spinPayout + slotCfg.wager; 
                usedSpecials++;
            }
        }

        return spinPayout;
    }

    /**
     * @dev Multiplier for 3 symbols.
     */
    function getSymbolMultiplier(SymbolType s1, SymbolType s2, SymbolType s3) internal pure returns (uint256) {
        // Three matches
        if (s1 == s2 && s2 == s3) {
            if (s1 == SymbolType.Symbol0) return 6900;
            if (s1 == SymbolType.Symbol1) return 5000;
            if (s1 == SymbolType.Symbol2) return 2500;
            if (s1 == SymbolType.Symbol3) return 1500;
            if (s1 == SymbolType.Symbol4) return 1000;
            if (s1 == SymbolType.Symbol5) return 500;
            if (s1 == SymbolType.Symbol6) return 300;
            if (s1 == SymbolType.Symbol7) return 100;
        }
        // Double matches
        if (s1 == s2 || s2 == s3) {
            SymbolType pairSymbol = (s1 == s2) ? s1 : s2;
            if (pairSymbol == SymbolType.Symbol0) return 1500;
            if (pairSymbol == SymbolType.Symbol1) return 1000;
            if (pairSymbol == SymbolType.Symbol2) return 500;
            if (pairSymbol == SymbolType.Symbol3) return 300;
            if (pairSymbol == SymbolType.Symbol4) return 200;
            if (pairSymbol == SymbolType.Symbol5) return 150; // 1.5 (но целочисленно → 1)
            if (pairSymbol == SymbolType.Symbol6) return 100;
            if (pairSymbol == SymbolType.Symbol7) return 50; // 0.5 (но целочисленно → 0)
        }
        // Special combinations
        if (s1 == SymbolType.Symbol0 && s3 == SymbolType.Symbol0) return 400;
        if (s2 == SymbolType.Symbol0) return 200;
        return 0;
    }

    function getReelSymbols(uint8 reelIndex, uint8 symbolIndex) external view returns (uint8) {
        if (reelIndex == 1) return reels[0][symbolIndex];
        if (reelIndex == 2) return reels[1][symbolIndex];
        if (reelIndex == 3) return reels[2][symbolIndex];

        revert("Invalid reel index");
    }

    /**
     * @dev Получаем базовый выигрыш (без учёта спецсимволов).
     */
    function getSpinWin(uint256 wager, bytes32 rnd) internal view returns (uint256 spinWin, bytes32 rndNext) {
        // Индексы на барабанах
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

    function setReels(uint8[16][3] memory newReels) external onlyOwner {
        reels = newReels;
    }

    /**
     * @dev Setter for specialConfig.
     */
    function setSpecialConfig(SlotsSpecialConfig memory newConfig) external onlyOwner {
        // Check reasonable limits
        require(newConfig.wildSymbolProbability <= 100, "Wild prob too high");
        require(newConfig.bonusSymbolProbability <= 100, "Bonus prob too high");
        require(newConfig.deadSymbolProbability <= 100, "Dead prob too high");
        require(newConfig.houseEdge <= 1000, "House edge too high"); // max 100%
        require(newConfig.specialSymbolsPerSpinLimit <= 3, "Too many special symbols");
    
        specialConfig = newConfig;
    }

    function getSpecialConfig() external view returns (SlotsSpecialConfig memory) {
        return specialConfig;
    }

}