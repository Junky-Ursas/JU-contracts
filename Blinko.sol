// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BaseGameContract.sol";

/// @title Blinko
/// @dev Contract for a Plinko game with three modes (conservative, balanced, YOLO).
contract BlinkoProxy is BaseGameContractProxy {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    uint256[13][3] public multipliers;
    // Example multipliers for 12 rows (13 holes). Index = hole number (0..12).
    // mode 0 = conservative, 1 = balanced, 2 = YOLO
    // conservative = [
    //     564, 329, 207, 150, 113, 85, 66, 85, 113, 150, 207, 329, 564
    // ];
    // balanced = [
    //     800, 400, 250, 160, 120, 80, 50, 80, 120, 160, 250, 400, 800
    // ];
    // yolo = [
    //     2120, 1060, 424, 212, 106, 63, 26, 63, 106, 212, 424, 1060, 2120
    // ];
    

    /// @dev Dividing the multiplier by 100 inside the function to avoid working with fractions
    /// (example: 564 = 5.64, 2120 = 21.20 and so on)

    /// @dev Instead of probability, we use mode. Validation that <3.
    modifier maxPayoutNotExceeded(uint256 wager, uint8 count, uint8 mode, address token) {
        require(mode < 3, "Invalid mode");

        uint256 maxMultiplier = multipliers[0][mode];
        // Simplified check for the maximum multiplier (take the YOLO extreme = 2120 = 21.2)
        // Approximate maximum: wager * (21.2) * count
        // Check that it does not exceed 1/20 of the treasury balance
        uint256 maxPossiblePayout = (wager * maxMultiplier * count) / 100; 
        require(maxPossiblePayout <= treasury.getBalance(token) / 50, "Max payout exceeded");
        _;
    }

    function playBlinko(GameConfig memory config)
        external
        payable
        maxPayoutNotExceeded(config.wager, config.count, config.extra, config.token)
        nonReentrant
    {
        // Check fee
        uint256 fee = entropy.getFee(entropyProvider);
        require(msg.value >= fee, "Insufficient fee");
        // Minimum bet
        require(config.wager * config.count >= minAmount, "Bet below minimum");

        // Если Ether, проверим, что денег хватит
        if (config.token == address(0)) {
            require(msg.value > fee, "Bet amount too low");
            uint256 netAmount = msg.value - fee;
            require(netAmount >= config.wager * config.count, "Bet amount too low");
        } else {
            IERC20 tokenContract = IERC20(config.token);
            uint256 allowance = tokenContract.allowance(msg.sender, address(this));
            require(allowance >= config.wager * config.count, "Allowance too low");
            tokenContract.transferFrom(msg.sender, address(this), config.wager * config.count);
        }

        // Request entropy
        uint64 sequenceNumber = entropy.requestWithCallback{value: fee}(entropyProvider, config.userRandomNumber);
        // Save config
        games[sequenceNumber] = abi.encode(config);

        emit GameStarted(sequenceNumber, msg.sender, config.wager, config.count, config.token, config.userRandomNumber);
        treasury.notifyGameStarted(sequenceNumber, msg.sender, config.wager, config.count, config.token);
    }

    /// @dev In entropyCallback, we calculate which hole the ball will fall into based on randomNumber.
    function entropyCallback(uint64 sequenceNumber, address, bytes32 randomNumber) internal override {
        GameConfig memory game = abi.decode(games[sequenceNumber], (GameConfig));
        Flags memory flags;
        flags.initialRandomNumber = randomNumber;

        // mode < 3 (0..2). Select the appropriate multiplier array
        uint256[13] memory currentTable = multipliers[game.extra];

        for (uint8 i = 0; i < game.count && flags.playedCount < 100; i++) {
            // Determine the hole (0..12), counting 12 levels, each level = 1 bit (left/right)
            uint256 path = 0;
            bytes32 localRand = randomNumber;
            for (uint8 level = 0; level < 12; level++) {
                // Берём младший бит и прибавляем к path
                path += (uint256(localRand) & 1);
                localRand >>= 1;
            }
            // Now path is the hole number. If it exceeds 12, take it modulo 13
            path = path % 13;

            // Payout = wager * multiplier / 100
            uint256 payout = (game.wager * currentTable[path]) / 100;
            flags.totalPayout += payout;
            if (payout > 0) {
                flags.wonCount++;
            }
            flags.playedCount++;

            // Shift randomNumber by 12 bits (or as you want)
            randomNumber >>= 12;
        }

        // Money for refund
        uint256 unplayedWager = game.wager * (game.count - flags.playedCount);
        uint256 totalRefund = flags.totalPayout + unplayedWager;

        if (totalRefund > 0) {
            treasury.requestPayout(game.player, totalRefund, game.token);
        }

        // Deposit in treasury
        uint256 totalWager = game.wager * game.count;
        if (game.token == address(0)) {
            treasury.deposit{value: totalWager}(totalWager);
        } else {
            IERC20 tokenContract = IERC20(game.token);
            tokenContract.approve(address(treasury), totalWager);
            treasury.transferFrom(game.token, address(this), address(treasury), totalWager);
        }

        emit GameResult(game.player, totalRefund, flags.initialRandomNumber, flags.wonCount, flags.playedCount, game.token);
        treasury.notifyGameResult(sequenceNumber, totalRefund, flags.initialRandomNumber, flags.wonCount, flags.playedCount, game.extra);
    }

    function setMultipliers(uint8 mode, uint256[13] memory _multipliers) external onlyOwner {
        require(mode < 3, "Invalid mode");
        multipliers[mode] = _multipliers;
    }

    function getMultipliers(uint8 mode) external view returns (uint256[13] memory) {
        require(mode < 3, "Invalid mode");
        return multipliers[mode];
    }
}
