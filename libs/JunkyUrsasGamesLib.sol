// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@pythnetwork/entropy-sdk-solidity/IEntropy.sol";
import "@pythnetwork/entropy-sdk-solidity/IEntropyConsumer.sol";
// import "../service/EntropyMock.sol";

import "../service/Bankroll.sol";
import "./JunkyUrsasEventsLib.sol";

/// @title BaseGameContract
/// @dev Сontract that implements core functionality for games using entropy and bankroll management.
abstract contract JunkyUrsasGamesLib is JunkyUrsasEventsLib, IEntropyConsumer {
    Bankroll internal bankroll;       // Bankroll contract for handling deposits and payouts
    IEntropy internal entropy;                // Entropy contract for randomness
    address internal entropyProvider; // Address of the entropy provider
    uint256 internal minBetAmount; // Minimum bet amount
    uint8 internal maxIterations; // Maximum number of iterations
    uint8 internal houseEdge; // Commission (in %)
    uint8 internal minProbability; // Minimum probability
    uint8 internal maxProbability; // Maximum probability
    uint8 internal holesCount; // Number of holes
    uint8 internal levelsCount; // Maximum number of levels
    uint256 internal maxWinPercentage; // Maximum win percentage

    mapping(uint64 sequenceNumber => bytes) internal games; // Mapping from sequence number to Game struct
    
    /// @dev Blinko multipliers
    uint256[13][3] internal blinkoMultipliers;

    /// @dev Special multipliers for JunkySlots
    uint16[3] internal junkySlotsV2SpecialMultipliers;
    // [69, 99, 36]
    /// @dev Multipliers for JunkySlots V2
    uint16[13] internal junkySlotsV2Multipliers;

    /// @dev Multipliers for JunkySlots Super
    uint16[18] internal junkySlotsSuperMultipliers;
    /// @dev Reels for JunkySlots Super
    uint16[16][3] internal junkySlotsSuperReels;
    /// @dev Stores the current configuration of special symbols for JunkySlots V2. Can be made a setter for changing.
    SlotsSpecialConfig internal junkySlotsSuperSpecialConfig;
    /// @dev Emitted when a game is started.

    /// @dev Modifier to ensure that the maximum payout does not exceed the treasury balance.
    /// @param config The parameters for the game
    modifier maxWagerNotExceeded(GameConfig memory config, uint256 maxMultiplier) {
        // Calculate the maximum payout based on the wager, count, probability, and house edge
        uint256 maxTotalWager = getMaxTotalWager(config, maxMultiplier);
        uint256 totalWager = config.wager * config.count;
        require(totalWager <= maxTotalWager, "Max wager exceeded");
        _;
    }

    /// @dev Constructor to initialize the BaseGameContractProxy contract.
    /// @param bankrollAddress The address of the bankroll contract
    /// @param entropyAddress The address of the entropy contract
    /// @param entropyProviderAddress The address of the entropy provider
    function initialize(address bankrollAddress, address entropyAddress, address entropyProviderAddress) 
        initializer public
    {
        // Initialize the contract state variables
        __Ownable_init(msg.sender); // Set the owner of the contract
        __ReentrancyGuard_init(); // Initialize the reentrancy guard
        bankroll = Bankroll(bankrollAddress); // Set the bankroll contract
        entropy = IEntropy(entropyAddress); // Set the entropy contract
        entropyProvider = entropyProviderAddress; // Set the entropy provider
        maxIterations = 70;
        minBetAmount = 1e16;
        houseEdge = 0;
        minProbability = 1;
        maxProbability = 70;
        holesCount = 13;
        levelsCount = 12;
        maxWinPercentage = 5;
        blinkoMultipliers = [
            [564, 329, 207, 150, 113, 85, 66, 85, 113, 150, 207, 329, 564],
            [800, 400, 250, 160, 120, 80, 50, 80, 120, 160, 250, 400, 800],
            [2120, 1060, 424, 212, 106, 63, 26, 63, 106, 212, 424, 1060, 2120]
        ];
        junkySlotsV2SpecialMultipliers = [69, 99, 36];
        junkySlotsV2Multipliers = [27, 22, 18, 9, 6, 6, 3, 2, 1, 1, 1, 1, 0];
        junkySlotsSuperMultipliers = [6900, 5000, 2500, 1500, 1000, 500, 300, 100, 1500, 1000, 500, 300, 200, 150, 100, 50, 400, 200];
        junkySlotsSuperReels = [
            [0,1,2,3,4,5,6,7,3,4,5,6,7,7,7,7],
            [0,1,2,3,4,5,6,7,2,3,4,5,6,7,7,7],
            [0,1,2,3,4,5,6,7,1,2,3,4,5,6,7,7]
        ];
        junkySlotsSuperSpecialConfig = SlotsSpecialConfig({
            wildSymbolProbability: 20,
            bonusSymbolProbability: 5,
            deadSymbolProbability: 20,
            wildMultiplier: 2,
            deadMultiplier: 0,
            specialSymbolsPerSpinLimit: 1
        });

    }

    /// @dev Handles deposits of wagers in either Ether or ERC20 tokens.
    /// @param config The parameters for the game
    /// @param msgValue The value of the message
    /// @param msgSender The address of the message sender
    /// @return The sequence number of the game
    function handleDeposit(GameConfig memory config, uint256 msgValue, address msgSender) 
        internal returns (uint64)
    {
        // Get the entropy fee
        uint256 fee = entropy.getFee(entropyProvider);
        // Get total wager 
        uint256 totalWager = config.wager * config.count;
        // Check that the fee is sufficient
        require(msgValue >= fee, "Insufficient fee");
        // Check that the bet amount is above the minimum required
        require(totalWager >= minBetAmount, "Bet amount is below the minimum required");
        // Check if the count is valid
        require(config.count < maxIterations, "Invalid count");

        require(config.player == msgSender, "Invalid player");
        require(config.player != address(0), "Invalid player");
        // Handle deposits of wagers in either Ether or ERC20 tokens
        if (config.token == address(0)) {
            // If the token is Ether
            require(msgValue > fee, "Bet amount too low");
            uint256 netAmount = msgValue - fee;
            require(netAmount >= totalWager, "Bet amount too low");
        } else {
            // If the token is an ERC20 token
            IERC20 tokenContract = IERC20(config.token);
            uint256 allowance = tokenContract.allowance(msgSender, address(this));
            require(allowance >= totalWager, "Allowance too low");
            tokenContract.transferFrom(msgSender, address(this), totalWager);
        }

        uint64 sequenceNumber = entropy.requestWithCallback{value: fee}(entropyProvider, config.userRandomNumber);
        return sequenceNumber;
    }

    /// @dev Handles the payout for a game.
    /// @param config The game configuration
    /// @param flags The game flags
    /// @return The total payout amount
    function handlePayout(GameConfig memory config, Flags memory flags) 
        internal returns (uint256)
    {
        // Calculate the unplayed wager amount
        uint256 unplayedWager = config.wager * (config.count - flags.playedCount);
        // Calculate the total refund amount
        uint256 totalPayout = (flags.totalPayout + unplayedWager) * (100 - houseEdge) / 100;
        // Handle deposits of wagers in either Ether or ERC20 tokens
        uint256 totalWager = config.wager * config.count;
        if (config.token == address(0)) {
            // If the token is Ether    
            bankroll.depositETH{value: totalWager}(address(this), totalWager);
        } else {
            // If the token is an ERC20 token
            IERC20 tokenContract = IERC20(config.token);
            tokenContract.approve(address(bankroll), totalWager);
            bankroll.depositERC20(config.token, address(this), totalWager);
        }
        // Request a payout from the treasury contract if there is a non-zero refund amount
        if (totalPayout > 0 && totalPayout <= getMaxWinPayout(config)) {
            bankroll.requestPayoutFromBankroll(config.player, totalPayout, config.token);
        }
        return totalPayout;
    }

    /// @notice Starts a new game of JunkySlots.
    /// @param config The game configuration, including wager, count, and extra parameters.
    /// @dev Validates and processes the game start request, emitting an event and notifying the bankroll.
    function playGame(GameConfig memory config)
        internal
    {
        // Set the timestamp of the game start
        config.timestamp = block.timestamp;
        // Handle deposit and generate a unique sequence number for the game
        uint64 sequenceNumber = handleDeposit(config, msg.value, msg.sender);
        // Store the game configuration
        games[sequenceNumber] = abi.encode(config);
        // Emit event to indicate game has started
        emit GameStarted(config, sequenceNumber);
        // Notify the bankroll about the game start
        bankroll.notifyGameStarted(
            config,
            sequenceNumber,
            address(this),
            block.timestamp
        );
    }

    function entropyCallback(uint64 sequenceNumber, address, bytes32 randomNumber) internal override {
        // Decode the game configuration
        require(games[sequenceNumber].length > 0, "Game not found");
        GameConfig memory config = abi.decode(games[sequenceNumber], (GameConfig));
        require(config.timestamp + 1000 > block.timestamp, "Resolve period over, refund money");
        
        Flags memory flags;
        flags.initialRandomNumber = randomNumber;

        // Call game logic
        Flags memory updatedFlags = calculateGameLogic(config, randomNumber, flags);

        // Handle payout
        uint256 finalPayout = handlePayout(config, updatedFlags);

        // Emit game result
        emit GameResult(
            config, 
            updatedFlags, 
            finalPayout, 
            sequenceNumber
        );

        // Notify bankroll
        bankroll.notifyGameResult(
            config, 
            updatedFlags,
            finalPayout,
            sequenceNumber,
            address(this),
            block.timestamp
        );

        delete games[sequenceNumber];
    }

    /// @dev Abstract function that each game must implement with its specific logic
    /// @return flags Updated game flags
    function calculateGameLogic(
        GameConfig memory config,
        bytes32 randomNumber,
        Flags memory flags
    ) internal virtual returns (Flags memory);
    
    function refund(uint64 sequenceNumber) external nonReentrant {
        GameConfig memory config = abi.decode(games[sequenceNumber], (GameConfig));
        require(config.timestamp + 1000 > block.timestamp, "Resolve period is not over yet");
        delete games[sequenceNumber];
        if (config.token == address(0)) {
            payable(config.player).transfer(config.wager * config.count);
        } else {
            IERC20 tokenContract = IERC20(config.token);
            tokenContract.transfer(config.player, config.wager * config.count);
        }
        emit GameCanceledAndRefunded(config, sequenceNumber);
    }

    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(amount);
        } else {
            IERC20(token).transfer(owner(), amount);
        }
        emit EmergencyWithdraw(token, amount);
    }

    /// @dev Sets the entropy provider address.
    /// @param newEntropyProvider The new entropy provider address
    function setEntropyProvider(address newEntropyProvider) external onlyOwner {
        entropyProvider = newEntropyProvider;
        emit EntropyProviderSet(newEntropyProvider);
    }

    /// @dev Returns the entropy provider address.
    /// @return The entropy provider address
    function getEntropyProvider() external view returns (address) {
        return entropyProvider;
    }

    /// @dev Sets the entropy contract address.
    /// @param newEntropy The new entropy contract address
    function setEntropy(address newEntropy) external onlyOwner {
        entropy = IEntropy(newEntropy);
        emit EntropySet(newEntropy);
    }
    
    /// @dev Returns the address of the entropy contract.
    /// @return The address of the entropy contract
    function getEntropy() internal view override returns (address) {
        return address(entropy);
    }

    /// @dev Sets the address of the bankroll contract.
    /// @param newBankroll The address of the new bankroll contract
    function setBankroll(address newBankroll) external onlyOwner {
        bankroll = Bankroll(newBankroll);
        emit BankrollSet(newBankroll);
    }

    /// @dev Returns the address of the bankroll contract.
    /// @return The address of the bankroll contract
    function getBankroll() external view returns (address) {
        return address(bankroll);
    }

    /// @dev Sets the maximum number of iterations.
    /// @param newMaxIterations The new maximum number of iterations
    function setMaxIterations(uint8 newMaxIterations) external onlyOwner {
        maxIterations = newMaxIterations;
        emit MaxIterationsSet(newMaxIterations);
    }

    /// @dev Returns the maximum number of iterations.
    /// @return The maximum number of iterations
    function getMaxIterations() external view returns (uint8) {
        return maxIterations;
    }

    /// @dev Sets the minimum bet amount.
    /// @param newMinBetAmount The new minimum bet amount
    function setMinBetAmount(uint256 newMinBetAmount) external onlyOwner {
        minBetAmount = newMinBetAmount;
        emit MinBetAmountSet(newMinBetAmount);
    }

    /// @dev Returns the minimum bet amount.
    /// @return The minimum bet amount
    function getMinBetAmount() external view returns (uint256) {
        return minBetAmount;
    }
    
    /// @dev Sets the house edge.
    /// @param newHouseEdge The new house edge
    function setHouseEdge(uint8 newHouseEdge) external onlyOwner {
        houseEdge = newHouseEdge;
        emit HouseEdgeSet(newHouseEdge);
    }

    /// @dev Returns the house edge.
    /// @return The house edge
    function getHouseEdge() external view returns (uint8) {
        return houseEdge;
    }

    /// @dev Sets the maximum win percentage.
    /// @param newMaxWinPercentage The new maximum win percentage
    function setMaxWinPercentage(uint256 newMaxWinPercentage) external onlyOwner {
        maxWinPercentage = newMaxWinPercentage;
        emit MaxWinPercentageSet(newMaxWinPercentage);
    }

    /// @dev Returns the maximum win percentage.
    /// @return The maximum win percentage
    function getMaxWinPercentage() external view returns (uint256) {
        return maxWinPercentage;
    }

    /// @dev Returns the maximum total wager.
    /// @param config The game configuration
    /// @param maxMultiplier The maximum multiplier
    /// @return The maximum total wager
    function getMaxTotalWager(GameConfig memory config, uint256 maxMultiplier) public view returns (uint256) {
        return bankroll.getBalance(config.token) / 100 * maxWinPercentage / maxMultiplier;
    }

    /// @dev Returns the maximum win payout.
    /// @param config The game configuration
    /// @return The maximum win payout
    function getMaxWinPayout(GameConfig memory config) public view returns (uint256) {
        return bankroll.getBalance(config.token) / 100 * maxWinPercentage;
    }

    function getEntropyAddress() external view returns (address) {
        return address(entropy);
    }

    /// @dev Fallback function to receive Ether.
    receive() external payable {}
}

