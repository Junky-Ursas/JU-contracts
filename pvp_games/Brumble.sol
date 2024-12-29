// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@pythnetwork/entropy-sdk-solidity/IEntropy.sol";
import "@pythnetwork/entropy-sdk-solidity/IEntropyConsumer.sol";

interface IOBRouter {
    /// @dev Struct for OBRouter swap info    
    struct swapTokenInfo {
        address inputToken;
        uint256 inputAmount;
        address outputToken;
        uint256 outputQuote;
        uint256 outputMin;
        address outputReceiver;
    }

    function swap(
        swapTokenInfo calldata tokenInfo, 
        bytes calldata pathDefinition, 
        address executor, 
        uint32 referralCode
    ) external payable returns (uint256 amountOut);
}

/// @title BrumbleGame
/// @dev A battle royale style game contract with elimination and resurrection mechanics
contract BrumbleGame is Initializable, ReentrancyGuardUpgradeable, IEntropyConsumer, OwnableUpgradeable {
     /// @dev Represents the state of a player.
    enum PlayerState {
        Normal,
        Vulnerable,
        Protected,
        Refunded
    }

    /// @dev Represents state of game 
    struct GameState {
        bool isStarted;
        bool isEnded;
        bool isRoundInProgress;
        uint256 currentRound;
        uint256 gameId;
        uint256 currentPrizePool;
        uint256 startTime;
        uint256 endTime;
        uint256 totalPlayers;
        uint256 alivePlayers;
    }

    /// @dev Represents a player in the game.
    struct Player {
        PlayerState state;
        bool isAlive;
    }

    /// @dev Represents a rount state info
    struct RoundState {
        bool isInProgress;
        uint256 roundNumber;
        uint256 alivePlayers;
        uint256 deadPlayers;
    }

    /// @dev Configuration settings for the game.
    struct GameConfig {
        uint8 minEliminationPercent; // Minimum elimination percentage (25%)
        uint8 maxEliminationPercent; // Maximum additional elimination percentage (35%)
        uint8 protectedStateChance; // Chance to receive Protected state (15%)
        uint8 vulnerableStateChance; // Chance to receive Vulnerable state (25%)
        uint8 resurrectionPercent; // Resurrection percentage (0%)
        uint8 gameEndPercent; // Percentage of alive players to end the game (40%)
        uint256 entryFee; // Entry fee in wei
        uint16 minPlayers; // Minimum number of players
        uint16 maxPlayers; // Maximum number of players
    }

    /// @dev Statistics of the game.
    struct GameStats {
        uint256 startTime;
        uint256 endTime;
        uint256 initialPlayers;
        uint256 totalRounds;
        uint256 totalEliminated;
        uint256 totalResurrected;
        uint256 finalPrizePool;
        bool completed;
    }

    /// @dev Game configuration parameters
    GameConfig private gameConfig;

    /// @dev Timestamp when the game ended
    uint256 private gameEndTime;

    /// @dev Mapping of game statistics by game ID
    mapping(uint256 => GameStats) private gameStats;

    /// @dev Mapping of player data by address
    mapping(address => Player) private players;

    /// @dev Array of all player addresses
    address[] public playerAddresses;

    /// @dev Current round number
    uint private roundNumber;

    /// @dev Flag indicating if the game has ended
    bool private gameEnded;

    /// @dev Initial number of players when game started
    uint private initialPlayerCount;

    /// @dev Flag indicating if the game has started
    bool private gameStarted;

    /// @dev Contract for random number generation
    IEntropy public entropy;

    /// @dev OBRouter contract
    IOBRouter public router;

    /// @dev Address of the entropy provider
    address public entropyProvider;

    /// @dev Total prize pool amount
    uint256 private prizePool;

    /// @dev House edge percentage for fee calculation
    uint256 public houseEdge;

    /// @dev Current game identifier
    uint256 private currentGameId;

    /// @dev Mapping of sequence numbers to game IDs for entropy callbacks
    mapping(uint64 => uint256) private sequenceNumberToGameId;   

    /// @dev Flag indicating if a round is in progress
    bool private roundInProgress;


    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract with entropy provider and game settings
    /// @param entropyAddress Address of the entropy contract
    /// @param entropyProviderAddress Address of the entropy provider
    function initialize(
        address entropyAddress,
        address entropyProviderAddress,
        address routerAddress
    ) public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        entropy = IEntropy(entropyAddress);
        entropyProvider = entropyProviderAddress;
        router = IOBRouter(routerAddress);
        houseEdge = 5;
        currentGameId = 1;
        roundNumber = 1;
        gameEnded = false;
        prizePool = 0;
        gameConfig = GameConfig({
            minEliminationPercent: 25,    /// @dev Minimum 1 player with 4 participants (25% of 4 = 1)
            maxEliminationPercent: 35,    /// @dev Maximum 1-2 players per round
            protectedStateChance: 15,     /// @dev Increased protection chance for balance
            vulnerableStateChance: 25,    /// @dev Increased vulnerability for faster gameplay
            resurrectionPercent: 0,       /// @dev Resurrections disabled
            gameEndPercent: 40,           /// @dev Game ends when 40% players remain
            entryFee: 0.01 ether,         /// @dev Entry stake amount
            minPlayers: 4,                /// @dev Minimum 4 players required
            maxPlayers: 10                /// @dev Maximum 100 players allowed
        });
    }

    /// @dev Allows a player to enter the game by paying the entry fee
    /// @notice Player must send exact entry fee amount
    function playBrumble() external payable nonReentrant {
        require(!gameStarted, "Game has already started");
        require(msg.value == gameConfig.entryFee, "Incorrect entry fee");
        require(players[msg.sender].isAlive == false, "Player already registered");
        require(playerAddresses.length < gameConfig.maxPlayers, "Maximum players limit reached");
        
        prizePool += msg.value;

        players[msg.sender] = Player({
            state: PlayerState.Normal,
            isAlive: true
        });
        playerAddresses.push(msg.sender);

        emit PlayerJoined(
            msg.sender,
            currentGameId,
            gameConfig.entryFee,
            msg.value
        );
    }

    /// @dev Allows a player to deposit ERC20 tokens to the game
    /// @param tokenInfo Swap token information.
    /// @param pathDefinition Swap path definition.
    /// @param executor Address of the executor.
    /// @param referralCode Referral code.
    function playBrumbleZap(
        IOBRouter.swapTokenInfo calldata tokenInfo,
        bytes calldata pathDefinition,
        address executor,
        uint32 referralCode
    ) external payable nonReentrant {
        require(!gameStarted, "Game has already started");
        require(players[msg.sender].isAlive == false, "Player already registered");
        require(playerAddresses.length < gameConfig.maxPlayers, "Maximum players limit reached");

        require(tokenInfo.outputToken == address(0), "Output token must be native token");
        require(tokenInfo.outputReceiver == address(this), "Output receiver must be contract address");

        bool transferSuccess = IERC20(tokenInfo.inputToken).transferFrom(msg.sender, address(this), tokenInfo.inputAmount);
        require(transferSuccess, "Transfer of input token failed");

        bool approveSuccess = IERC20(tokenInfo.inputToken).approve(address(router), tokenInfo.inputAmount);
        require(approveSuccess, "Approve failed");

        uint256 amountOut = router.swap{value: msg.value}(tokenInfo, pathDefinition, executor, referralCode);
        require(amountOut > gameConfig.entryFee*95/100, "Not enough tokens swapped");

        prizePool += amountOut;

        players[msg.sender] = Player({
            state: PlayerState.Normal,
            isAlive: true
        });
        playerAddresses.push(msg.sender);

        emit PlayerJoined(
            msg.sender,
            currentGameId,
            gameConfig.entryFee,
            amountOut
        );
    }

    /// @dev Starts the game if minimum requirements are met
    /// @notice Only owner can start the game
    function startBrumble() external onlyOwner {
        require(!gameStarted, "Game already started");
        uint256 activePlayers = getAlivePlayerCount();
        require(activePlayers >= gameConfig.minPlayers, "Not enough players");
        require(activePlayers <= gameConfig.maxPlayers, "Too many players");

        gameStarted = true;
        initialPlayerCount = activePlayers;

        gameStats[currentGameId] = GameStats({
            startTime: block.timestamp,
            endTime: 0,
            initialPlayers: playerAddresses.length,
            totalRounds: 0,
            totalEliminated: 0,
            totalResurrected: 0,
            finalPrizePool: prizePool,
            completed: false
        });

        emit GameInitialized(currentGameId, block.timestamp, gameConfig);
    }

    /// @dev Initiates a round execution by requesting random number from entropy provider
    /// @notice Requires payment for entropy fee
    function roundBrumble() public onlyOwner payable {
        require(gameStarted, "Game not started");
        require(!gameEnded, "Game has already ended");
        require(!roundInProgress, "Previous round still in progress");

        uint256 fee = entropy.getFee(entropyProvider);
        require(msg.value >= fee, "Insufficient fee");

        roundInProgress = true;
        bytes32 userRandomNumber = keccak256(abi.encodePacked(block.timestamp, msg.sender));
        uint64 sequenceNumber = entropy.requestWithCallback{value: fee}(entropyProvider, userRandomNumber);
        sequenceNumberToGameId[sequenceNumber] = currentGameId;

        emit RoundStarted(currentGameId, roundNumber, userRandomNumber, sequenceNumber, playerAddresses.length, playerAddresses);
    }

    /// @dev Callback function that receives random number from entropy provider
    /// @param sequenceNumber Sequence number of the entropy request
    /// @param randomNumber The generated random number
    function entropyCallback(uint64 sequenceNumber, address, bytes32 randomNumber) internal override {
        uint256 gameId = sequenceNumberToGameId[sequenceNumber];
        require(gameId == currentGameId, "Invalid gameId");

        _executeRoundWithRandom(randomNumber);
    }

    /// @dev Executes a round with the received random number
    /// @param R The received random number
    function _executeRoundWithRandom(bytes32 R) internal {
        uint N = getAlivePlayerCount();

        uint8 R1 = uint8(uint256(R) >> 251);
        uint8 P = gameConfig.minEliminationPercent + (R1 % (gameConfig.maxEliminationPercent - gameConfig.minEliminationPercent));

        uint K = (N * P) / 100;
        if (K == 0 && N > 0) K = 1;

        uint totalRiskFactor = 0;
        uint[] memory riskFactors = new uint[](N);
        address[] memory alivePlayers = new address[](N);
        uint256[] memory riskBounds = new uint256[](N + 1);
        uint index = 0;

        for (uint i = 0; i < playerAddresses.length; i++) {
            Player storage player = players[playerAddresses[i]];
            if (player.isAlive) {
                alivePlayers[index] = playerAddresses[i];
                uint riskFactor = player.state == PlayerState.Normal ? 1 :
                                  player.state == PlayerState.Vulnerable ? 2 : 0;
                riskFactors[index] = riskFactor;
                totalRiskFactor += riskFactor;
                riskBounds[index + 1] = totalRiskFactor;
                index++;
            }
        }

        (uint eliminatedCount) = processElimination(
            R,
            N,
            K,
            totalRiskFactor,
            riskBounds,
            alivePlayers,
            riskFactors
        );

        (uint resurrectedCount) = processResurrection(R);

        resetAndAssignRiskFactors(R);

        gameStats[currentGameId].totalEliminated += eliminatedCount;
        gameStats[currentGameId].totalResurrected += resurrectedCount;
        gameStats[currentGameId].totalRounds++; 
        emit RoundExecuted(currentGameId, roundNumber, N, R);

        N = N - eliminatedCount + resurrectedCount;
        if (N <= (initialPlayerCount * gameConfig.gameEndPercent) / 100) {
            gameEnded = true;
            gameEndTime = block.timestamp;
            emit GameEnded(currentGameId, roundNumber, getAlivePlayers(), prizePool);
            roundInProgress = false;
            return;
        }

        roundNumber++;
        roundInProgress = false;
    }

    /// @dev Resets the state of players and assigns new risk factors
    /// @param R The received random number
    function resetAndAssignRiskFactors(bytes32 R) internal {
        uint N = getAlivePlayerCount();
        if (N == 0) {
            return;
        }

        address[] memory alivePlayers = getAlivePlayers();

        for (uint i = 0; i < N; i++) {
            Player storage player = players[alivePlayers[i]];

            player.state = PlayerState.Normal;

            bytes32 stateHash = keccak256(
                abi.encodePacked(R, alivePlayers[i], roundNumber, "state")
            );
            uint8 stateValue = uint8(uint256(stateHash) % 100);

            if (stateValue < gameConfig.protectedStateChance) {
                player.state = PlayerState.Protected;
                emit PlayerBecameProtected(currentGameId, roundNumber, alivePlayers[i], player.state);
            } else if (
                stateValue <
                (gameConfig.protectedStateChance +
                    gameConfig.vulnerableStateChance)
            ) {
                player.state = PlayerState.Vulnerable;
                emit PlayerBecameVulnerable(currentGameId, roundNumber, alivePlayers[i], player.state);
            } else {
                player.state = PlayerState.Normal;
                emit PlayerBecameNormal(currentGameId, roundNumber, alivePlayers[i], player.state);
            }
        }
    }

    /// @dev Distributes prizes to the winners immediately
    function finishBrumble() external onlyOwner nonReentrant {
        require(gameEnded, "Game not ended yet");
        require(prizePool > 0, "No prizes to distribute");
        require(!gameStats[currentGameId].completed, "Prizes already distributed");

        address[] memory winners = getAlivePlayers();
        require(winners.length > 0, "No winners found");

        uint256 protocolFee = (prizePool * houseEdge) / 100;
        (bool _success, ) = payable(owner()).call{value: protocolFee}("");
        require(_success, "Owner fee transfer failed");

        prizePool -= protocolFee;

        uint256 prizePerWinner = prizePool / winners.length;
        uint256 remainder = prizePool - (prizePerWinner * winners.length);

        // Send prizes to winners
        for (uint i = 0; i < winners.length; i++) {
            (bool success, ) = winners[i].call{value: prizePerWinner}("");
            require(success, "Prize transfer failed");
        }

        // Send remainder to the first winner
        if (remainder > 0) {
            (bool success, ) = winners[0].call{value: remainder}("");
            require(success, "Remainder transfer failed");
        }

        gameStats[currentGameId].completed = true;
        gameStats[currentGameId].endTime = block.timestamp;
        gameStats[currentGameId].finalPrizePool = prizePool;
        prizePool = 0;

        emit PrizesDistributed(
            currentGameId,
            winners,
            prizePerWinner,
            remainder
        );

        emit GameStatistics(
            currentGameId,
            gameStats[currentGameId].totalRounds,
            gameStats[currentGameId].initialPlayers,
            winners.length,
            prizePool,
            prizePerWinner,
            block.timestamp,
            winners
        );

        resetGame();
    }

    /// @dev Emergency ends the game and returns entry fees to all participants
    function emergencyEndGame() external onlyOwner nonReentrant {
        for (uint i = 0; i < playerAddresses.length; i++) {
            address player = playerAddresses[i];
            (bool success, ) = player.call{value: gameConfig.entryFee}("");
            require(success, "Refund transfer failed");
        }

        gameEnded = true;
        gameEndTime = block.timestamp;
        gameStats[currentGameId].completed = true;
        gameStats[currentGameId].endTime = block.timestamp;

        emit GameEnded(
            currentGameId,
            roundNumber,
            playerAddresses,
            prizePool
        );

        resetGame();
    }

    /// @dev Resets the game state
    function resetGame() internal {
        require(gameEnded, "Game not ended yet");

        currentGameId++;

        for (uint i = 0; i < playerAddresses.length; i++) {
            delete players[playerAddresses[i]];
        }

        delete playerAddresses;
        gameStarted = false;
        gameEnded = false;
        roundNumber = 1;
        initialPlayerCount = 0;
        prizePool = 0;
        gameEndTime = 0;
        
        roundInProgress = false;
        
        emit GameReset(currentGameId - 1, currentGameId, block.timestamp);
    }

    /// @dev Returns the address of the entropy contract
    /// @return The address of the entropy contract
    function getEntropy() internal view override returns (address) {
        return address(entropy);
    }

    /// @dev Fallback function to receive Ether
    receive() external payable {}

    /// @dev Emitted when the game configuration is updated.
    event GameConfigUpdated(
        uint8 minEliminationPercent,
        uint8 maxEliminationPercent,
        uint8 protectedStateChance,
        uint8 vulnerableStateChance,
        uint8 resurrectionPercent,
        uint8 gameEndPercent,
        uint256 entryFee
    );

    /// @dev Emitted when a player joins the game.
    event PlayerJoined(
        address indexed player,
        uint256 indexed gameId,
        uint256 entryFee,
        uint256 prizePoolContribution
    );
    
    /// @dev Emitted when a round is executed.
    event RoundExecuted(
        uint256 indexed gameId,
        uint256 indexed roundNumber,
        uint256 alivePlayersCount,
        bytes32 randomNumber
    );

    /// @dev Emitted when a round starts.
    event RoundStarted(
        uint256 indexed gameId,
        uint256 indexed roundNumber,
        bytes32 randomSeed,
        uint256 sequenceNumber,
        uint256 alivePlayersCount,
        address[] alivePlayers
    );

    /// @dev Emitted when a player is eliminated.
    event PlayerEliminated(
        uint256 indexed gameId,
        uint256 indexed roundNumber,
        address indexed player
    );

    /// @dev Emitted when a player is resurrected.
    event PlayerResurrected(
        uint256 indexed gameId,
        uint256 indexed roundNumber,
        address indexed player
    );

    /// @dev Emitted when a player's state changes.
    event PlayerBecameProtected(
        uint256 indexed gameId,
        uint256 indexed roundNumber,
        address indexed player,
        PlayerState newState
    );

    /// @dev Emitted when a player's state changes.
    event PlayerBecameVulnerable(
        uint256 indexed gameId,
        uint256 indexed roundNumber,
        address indexed player,
        PlayerState newState
    );

    /// @dev Emitted when a player's state changes.
    event PlayerBecameNormal(
        uint256 indexed gameId,
        uint256 indexed roundNumber,
        address indexed player,
        PlayerState newState
    );

    /// @dev Emitted when the game ends.
    event GameEnded(
        uint256 indexed gameId,
        uint256 finalRound,
        address[] winners,
        uint256 prizePool
    );

    /// @dev Emitted when prizes are distributed to the winners.
    event PrizesDistributed(
        uint256 indexed gameId,
        address[] winners,
        uint256 prizePerWinner,
        uint256 remainder
    );

    /// @dev Emitted when the game is reset.
    event GameReset(
        uint256 indexed oldGameId,
        uint256 indexed newGameId,
        uint256 timestamp
    );

    /// @dev Emitted when game statistics are updated.
    event GameStatistics(
        uint256 indexed gameId,
        uint256 totalRounds,
        uint256 initialPlayers,
        uint256 finalPlayers,
        uint256 totalPrizePool,
        uint256 prizePerWinner,
        uint256 timestamp,
        address[] winners
    );

    /// @dev Emitted when the game is initialized.
    event GameInitialized(
        uint256 indexed gameId,
        uint256 timestamp,
        GameConfig config
    );

    /// @dev Performs a binary search on a sorted array to find the index of the target.
    /// @param arr The sorted array to search.
    /// @param target The value to search for.
    /// @return The index of the target if found, otherwise the closest lower index.
    function binarySearch(
        uint256[] memory arr,
        uint256 target
    ) internal pure returns (uint) {
        uint left = 0;
        uint right = arr.length - 1;

        while (left < right) {
            uint mid = (left + right) / 2;
            if (arr[mid] > target) {
                right = mid;
            } else {
                left = mid + 1;
            }
        }
        return left - 1;
    }

    /// @dev Processes the elimination of players based on risk factors.
    /// @param R The random number used for elimination.
    /// @param N The number of alive players.
    /// @param K The number of players to eliminate.
    /// @param totalRiskFactor The total risk factor of all players.
    /// @param riskBounds The cumulative risk bounds for players.
    /// @param alivePlayers An array of alive player addresses.
    /// @param riskFactors An array of risk factors corresponding to alive players.
    /// @return The array of eliminated player addresses and the count of eliminations.
    function processElimination(
        bytes32 R,
        uint N,
        uint K,
        uint256 totalRiskFactor,
        uint256[] memory riskBounds,
        address[] memory alivePlayers,
        uint256[] memory riskFactors
    ) internal returns (uint) {
        address[] memory eliminated = new address[](K);
        uint count = 0;
        uint256 cumulativeRisk = totalRiskFactor;

        while (count < K && cumulativeRisk > 0) {
            uint256 randomValue = uint256(
                keccak256(abi.encodePacked(R, N, count))
            ) % cumulativeRisk;
            uint playerIndex = binarySearch(riskBounds, randomValue);
            address playerAddr = alivePlayers[playerIndex];

            if (playerAddr != address(0) && 
                riskFactors[playerIndex] > 0 && 
                players[playerAddr].state != PlayerState.Refunded) 
            {
                eliminated[count] = playerAddr;
                players[playerAddr].isAlive = false;
                count++;
                cumulativeRisk -= riskFactors[playerIndex];
                riskFactors[playerIndex] = 0;
                emit PlayerEliminated(currentGameId, roundNumber, playerAddr);
            }
        }

        return (count);
    }

    /// @dev Resurrects eliminated players
    /// @param R The received random number
    function processResurrection(bytes32 R) internal returns (uint) {
        uint aliveCount = getAlivePlayerCount();
        uint totalDeadPlayers = initialPlayerCount - aliveCount;

        // If there are less than 1 dead players, resurrection is not possible
        if (totalDeadPlayers < 1) {
            return 0;
        }

        // Use resurrectionPercent as the chance that resurrection will happen
        bytes32 H = keccak256(
            abi.encodePacked(R, roundNumber, "resurrection_chance")
        );
        uint256 randomChance = uint256(H) % 100;

        // If the random number is greater than the resurrection chance, exit
        if (randomChance >= gameConfig.resurrectionPercent) {
            return 0;
        }

        // If resurrection should happen, select one random dead player
        address[] memory deadPlayers = getDeadPlayers();
        bytes32 H2 = keccak256(
            abi.encodePacked(R, roundNumber, "resurrection_player")
        );
        uint256 randomIndex = uint256(H2) % totalDeadPlayers;
        
        // Resurrect the selected player
        address playerToResurrect = deadPlayers[randomIndex];
        players[playerToResurrect].isAlive = true;
        emit PlayerResurrected(currentGameId, roundNumber, playerToResurrect);

        return 1;
    }

    /// @dev Sets the house edge percentage
    /// @param newEdge The new house edge percentage
    function setHouseEdge(uint256 newEdge) external onlyOwner {
        houseEdge = newEdge;
    }

    /// @dev Updates the game configuration parameters
    /// @param _minEliminationPercent Minimum percentage of players to eliminate per round
    /// @param _maxEliminationPercent Maximum percentage of players to eliminate per round
    /// @param _protectedStateChance Chance for a player to receive protected state
    /// @param _vulnerableStateChance Chance for a player to receive vulnerable state
    /// @param _resurrectionPercent Chance for eliminated players to resurrect
    /// @param _gameEndPercent Percentage of remaining players to end the game
    /// @param _entryFee Required entry fee in wei
    /// @param _minPlayers Minimum number of players required
    /// @param _maxPlayers Maximum number of players allowed
    function setGameConfig(
        uint8 _minEliminationPercent,
        uint8 _maxEliminationPercent,
        uint8 _protectedStateChance,
        uint8 _vulnerableStateChance,
        uint8 _resurrectionPercent,
        uint8 _gameEndPercent,
        uint256 _entryFee,
        uint16 _minPlayers,
        uint16 _maxPlayers
    ) external onlyOwner {
        require(!gameStarted, "Cannot change config after game started");
        require(
            _minEliminationPercent > 0 && _minEliminationPercent <= 100,
            "Invalid minEliminationPercent"
        );
        require(_maxEliminationPercent <= 100, "Invalid maxEliminationPercent");
        require(_protectedStateChance <= 100, "Invalid protectedStateChance");
        require(_vulnerableStateChance <= 100, "Invalid vulnerableStateChance");
        require(_resurrectionPercent <= 100, "Invalid resurrectionPercent");
        require(_gameEndPercent <= 100, "Invalid gameEndPercent");
        require(_minPlayers >= 2, "Min players must be at least 2");
        require(
            _maxPlayers >= _minPlayers,
            "Max players must be >= min players"
        );
        require(_maxPlayers <= 1000, "Max players cannot exceed 1000");

        gameConfig = GameConfig({
            minEliminationPercent: _minEliminationPercent,
            maxEliminationPercent: _maxEliminationPercent,
            protectedStateChance: _protectedStateChance,
            vulnerableStateChance: _vulnerableStateChance,
            resurrectionPercent: _resurrectionPercent,
            gameEndPercent: _gameEndPercent,
            entryFee: _entryFee,
            minPlayers: _minPlayers,
            maxPlayers: _maxPlayers
        });

        emit GameConfigUpdated(
            _minEliminationPercent,
            _maxEliminationPercent,
            _protectedStateChance,
            _vulnerableStateChance,
            _resurrectionPercent,
            _gameEndPercent,
            _entryFee
        );
    }

    /// @dev Returns current game state information
    function getGameState() external view returns (GameState memory) {
        return (
            GameState(   
                gameStarted,
                gameEnded,
                roundInProgress,
                roundNumber,
                currentGameId,
                prizePool,
                gameStats[currentGameId].startTime,
                gameEndTime,
                initialPlayerCount,
                getAlivePlayerCount()
            )
        );
    }

    /// @dev Returns player state information
    function getPlayerState(address player) external view returns (Player memory) {
        return players[player];
    }

    /// @dev Returns all registered players for current game
    function getAllPlayers() external view returns (address[] memory) {
        return playerAddresses;
    }

    /// @dev Returns current round state information
    function getRoundState() external view returns (RoundState memory) {
        uint256 alive = getAlivePlayerCount();
        return (
            RoundState(
                roundInProgress,
                roundNumber,
                alive,
                initialPlayerCount - alive
            )
        );
    }

    /// @dev Returns the game statistics
    function getGameStatistics(
        uint256 gameId
    )
        external
        view
        returns (GameStats memory)
    {
        return gameStats[gameId];
    }

    /// @dev Returns the game configuration
    /// @return The game configuration
    function getGameConfig() external view returns (GameConfig memory) {
        return gameConfig;
    }

    /// @dev Returns the number of alive players
    /// @return The number of alive players
    function getAlivePlayerCount() public view returns (uint) {
        uint count = 0;
        for (uint i = 0; i < playerAddresses.length; i++) {
            if (players[playerAddresses[i]].isAlive && 
                players[playerAddresses[i]].state != PlayerState.Refunded) {
                count++;
            }
        }
        return count;
    }

    /// @dev Returns the list of alive players
    /// @return The list of alive players
    function getAlivePlayers() public view returns (address[] memory) {
        uint N = getAlivePlayerCount();
        address[] memory alivePlayers = new address[](N);
        uint index = 0;
        for (uint i = 0; i < playerAddresses.length; i++) {
            if (players[playerAddresses[i]].isAlive && 
                players[playerAddresses[i]].state != PlayerState.Refunded) 
            {
                alivePlayers[index] = playerAddresses[i];
                index++;
            }
        }
        return alivePlayers;
    }

    /// @dev Returns the list of refunded players
    /// @return The list of refunded players
    function getRefundedPlayers() public view returns (address[] memory) {
        uint N = getAlivePlayerCount();
        address[] memory refundedPlayers = new address[](N);
        uint index = 0;
        for (uint i = 0; i < playerAddresses.length; i++) {
            if (!players[playerAddresses[i]].isAlive && 
                players[playerAddresses[i]].state == PlayerState.Refunded) {
                refundedPlayers[index] = playerAddresses[i];
                index++;
            }
        }
        return refundedPlayers;
    }

    /// @dev Returns the list of dead players
    /// @return The list of dead players
    function getDeadPlayers() public view returns (address[] memory) {
        uint N = getAlivePlayerCount();
        uint totalDeadPlayers = initialPlayerCount - N;
        address[] memory deadPlayers = new address[](totalDeadPlayers);
        uint deadIndex = 0;
        for (uint i = 0; i < playerAddresses.length; i++) {
            if (!players[playerAddresses[i]].isAlive && 
                players[playerAddresses[i]].state != PlayerState.Refunded) {
                deadPlayers[deadIndex] = playerAddresses[i];
                deadIndex++;
            }
        }
        return deadPlayers;
    }

    /// @dev Sets the current game ID
    /// @param _gameId The new game ID
    function setGameId(uint256 _gameId) external onlyOwner {
        currentGameId = _gameId;
    }

    /// @dev Refunds a player's entry fee
    function refundBrumble() external nonReentrant {
        require(gameStarted == false, "Game has already started");
        require(players[msg.sender].isAlive == true, "Player not registered");
        require(players[msg.sender].state != PlayerState.Refunded, "Already refunded");
        
        (bool success, ) = msg.sender.call{value: gameConfig.entryFee}("");
        require(success, "Refund transfer failed");
        
        players[msg.sender].state = PlayerState.Refunded;
        players[msg.sender].isAlive = false;
        initialPlayerCount--;
        
        prizePool -= gameConfig.entryFee;
        
        emit PlayerRefunded(currentGameId, msg.sender, gameConfig.entryFee);
    }

    event PlayerRefunded(
        uint256 indexed gameId,
        address indexed player,
        uint256 amount
    );
}
