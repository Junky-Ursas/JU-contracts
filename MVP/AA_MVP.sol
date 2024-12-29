// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "hardhat/console.sol";

/// @title VaultToken - ERC20 Token for Vaults
contract VaultTokenSM is ERC20, Ownable {
    /// @dev Constructor to initialize the VaultToken
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param owner The address of the owner
    constructor(string memory name, string memory symbol, address owner) ERC20(name, symbol) Ownable(owner) {
        transferOwnership(owner);
    }

    /// @dev Function to mint new tokens
    /// @param to The address to receive the tokens
    /// @param amount The amount of tokens to mint
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
        emit Mint(to, amount);
    }

    /// @dev Function to burn tokens
    /// @param from The address to burn tokens from
    /// @param amount The amount of tokens to burn
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
        emit Burn(from, amount);
    }

    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);
}

abstract contract IEntropyConsumer {
    // This method is called by Entropy to provide the random number to the consumer.
    // It asserts that the msg.sender is the Entropy contract. It is not meant to be
    // override by the consumer.
    function _entropyCallback(
        uint64 sequence,
        address provider,
        bytes32 randomNumber
    ) external {
        address entropy = getEntropy();
        require(entropy != address(0), "Entropy address not set");
        require(msg.sender == entropy, "Only Entropy can call this function");

        entropyCallback(sequence, provider, randomNumber);
    }

    // getEntropy returns Entropy contract address. The method is being used to check that the
    // callback is indeed from Entropy contract. The consumer is expected to implement this method.
    // Entropy address can be found here - https://docs.pyth.network/entropy/contract-addresses
    function getEntropy() internal view virtual returns (address);

    // This method is expected to be implemented by the consumer to handle the random number.
    // It will be called by _entropyCallback after _entropyCallback ensures that the call is
    // indeed from Entropy contract.
    function entropyCallback(
        uint64 sequence,
        address provider,
        bytes32 randomNumber
    ) internal virtual;
}

interface IEntropy {
    function requestWithCallback() external returns(uint64);
}

contract EntropySM is IEntropy {
    address sender;

    function requestWithCallback(
    ) public override returns (uint64) {
        sender = msg.sender;
        return uint64(block.number);
    }

    function revealWithCallback(
        address provider,
        uint64 sequenceNumber,
        bytes32 randomNumber
    ) public {
        IEntropyConsumer(sender)._entropyCallback(
            sequenceNumber,
            provider,
            randomNumber
        );
    }
}

interface ITreasury {
    function notifyGameStarted(uint64 seq, address player, uint256 wager, uint8 count, address token) external;
    function notifyGameResult(uint64 seq, uint256 payout, bytes32 rnd, uint8 wonCount, uint8 played, uint8 prob) external;
    function requestPayout(address player, uint256 amount, address token) external;
}



/// @title TreasuryContract
/// @dev Manages deposits, payouts, and liquidity for whitelisted entities.
contract TreasurySM is Ownable, ReentrancyGuard {
    mapping(address => bool) public whitelistedEntities;
    mapping(address => uint256) public tokenBalances;
    mapping(address => bool) public whitelistedTokens;
    uint256 public houseEdge;
    bool public withdrawalsFrozen;

    address public feeRecipient = 0x0000000000000000000000000000000000000001;  
    uint256 public feePercentage; 
    event GlobalGameStarted(
        uint64 sequenceNumber,
        address indexed game,
        address indexed player,
        uint256 wager,
        uint8 count,
        address indexed token
    );

    event GlobalGameResult(
        uint64 indexed sequenceNumber,
        uint256 payout,
        bytes32 randomNumber,
        uint8 wonCount,
        uint8 totalCount,
        uint8 userInput
    );

    event Deposit(address indexed user, uint256 amount, address indexed token);
    event Payout(address indexed user, uint256 amount, address indexed token);
    event WhitelistedEntity(address indexed entity);
    event RemovedFromWhitelist(address indexed entity);
    event TokenWhitelisted(address indexed token);
    event TokenRemovedFromWhitelist(address indexed token);
    event WithdrawalsFrozen();
    event WithdrawalsUnfrozen();
    event VMLiquidityAdded(address indexed userAddress, address indexed liqTokenAddress, uint256 liqTokenAmount, uint256 vaultTokensAmount);
    event VMLiquidityRemoved(address indexed userAddress, address indexed liqTokenAddress, uint256 liqTokenAmount, uint256 vaultTokensAmount);
    event VMVaultCreated(address indexed vaultTokenAddress, address indexed liqTokenAddress);

    /// @dev Modifier to restrict actions to only whitelisted entities.
    modifier onlyWhitelistedEntities() {
        require(whitelistedEntities[msg.sender], "Not a whitelisted entity");
        _;
    }

    /// @dev Modifier to ensure the token is whitelisted.
    /// @param token Address of the token to check.
    modifier onlyWhitelistedTokens(address token) {
        require(whitelistedTokens[token], "Token not whitelisted");
        _;
    }

    function whitelistEntity(address entity) external onlyOwner {
        whitelistedEntities[entity] = true;
        emit WhitelistedEntity(entity);
    }

    function whitelistToken(address token) external onlyOwner {
        whitelistedTokens[token] = true;
        emit TokenWhitelisted(token);
    }

    constructor() Ownable(msg.sender) {
        feePercentage = 100; // 1%
    }

    /// @dev Allows a whitelisted entity to deposit ETH.
    /// @param amount Amount of ETH to deposit.
    function deposit(uint256 amount) external payable nonReentrant onlyWhitelistedEntities {
        require(msg.value == amount, "Invalid ETH amount");
        tokenBalances[address(0)] += msg.value;
        emit Deposit(msg.sender, amount, address(0));
    }

    /// @dev Allows a whitelisted entity to transfer tokens.
    /// @param token Address of the token.
    /// @param from Address to transfer from.
    /// @param to Address to transfer to.
    /// @param amount Amount to transfer.
    function transferFrom(address token, address from, address to, uint256 amount) external nonReentrant onlyWhitelistedTokens(token) onlyWhitelistedEntities {
        require(VaultTokenSM(token).transferFrom(from, to, amount), "Transfer failed");
        tokenBalances[token] += amount;
        emit Deposit(msg.sender, amount, token);
    }

    /// @dev Allows a whitelisted entity to request a payout.
    /// @param user Address of the user to pay out.
    /// @param amount Amount to pay out.
    /// @param token Address of the token to pay out.
    function requestPayout(address user, uint256 amount, address token) external onlyWhitelistedEntities nonReentrant {
        require(tokenBalances[token] >= amount, "Insufficient balance");

        uint256 fee = (amount * feePercentage) / 10000; 
        uint256 payoutAmount = amount - fee; 

        tokenBalances[token] -= amount;
        
        if (token == address(0)) {
            payable(feeRecipient).transfer(fee);
            payable(user).transfer(payoutAmount);
        } else {
            require(VaultTokenSM(token).transfer(feeRecipient, fee), "Fee transfer failed");
            require(VaultTokenSM(token).transfer(user, payoutAmount), "Payout transfer failed");
        }

        emit Payout(user, payoutAmount, token);
    }

    /// @dev Emits an event to notify that a global game has started.
    /// @param sequenceNumber Sequence number of the game.
    /// @param player Address of the player.
    /// @param wager Amount wagered.
    /// @param count Count of the event.
    /// @param token Address of the token used.
    function notifyGameStarted(
        uint64 sequenceNumber,
        address player,
        uint256 wager,
        uint8 count,
        address token
    ) external onlyWhitelistedEntities {
        emit GlobalGameStarted(sequenceNumber, msg.sender, player, wager, count, token);
    }

    /// @dev Emits an event to notify the result of a global game.
    /// @param sequenceNumber Sequence number of the game.
    /// @param payout Payout amount.
    /// @param randomNumber Random number used.
    /// @param wonCount Count of won games.
    /// @param totalCount Total count of games.
    /// @param userInput User input for the game.
    function notifyGameResult(
        uint64 sequenceNumber,
        uint256 payout,
        bytes32 randomNumber,
        uint8 wonCount,
        uint8 totalCount,
        uint8 userInput
    ) external onlyWhitelistedEntities {
        emit GlobalGameResult(sequenceNumber, payout - payout * feePercentage / 10000, randomNumber, wonCount, totalCount, userInput);
    }
}


contract SessionManagerSM {
    struct SessionKey { uint256 expires; }
    mapping(address => mapping(address => SessionKey)) public sessionKeys;
    mapping(address => uint256) public nonces;

    event SessionKeyAdded(address indexed user, address indexed key, uint256 expires);
    event SessionKeyRemoved(address indexed user, address indexed key);

    function addSessionKey(address key, uint256 duration) external {
        sessionKeys[msg.sender][key].expires = block.timestamp + duration;
        emit SessionKeyAdded(msg.sender, key, sessionKeys[msg.sender][key].expires);
    }

    function removeSessionKey(address key) external {
        require(sessionKeys[msg.sender][key].expires > 0, "No key");
        delete sessionKeys[msg.sender][key];
        emit SessionKeyRemoved(msg.sender, key);
    }

    // Проверка, что msg.sender — владелец или сессионный ключ
    function isAuthorized(address user, address relayer) external view returns(bool) {
        if (msg.sender == user) return true;
        SessionKey memory sk = sessionKeys[user][relayer];
        return (sk.expires > block.timestamp);
    }

    function getMessageHash(address user, uint256 amount) public view returns(bytes32) {
        return keccak256(abi.encodePacked(user, amount, nonces[user]));
    }
    function getEthSignedMessageHash(bytes32 h) public pure returns(bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h));
    }
    function recoverSigner(bytes32 ethHash, bytes memory signature) public pure returns(address) {
        require(signature.length == 65, "Bad sig len");
        bytes32 r; bytes32 s; uint8 v;
        assembly {
            r := mload(add(signature,32))
            s := mload(add(signature,64))
            v := byte(0,mload(add(signature,96)))
        }
        return ecrecover(ethHash, v, r, s);
    }

    function incrementNonce(address user) external {
        nonces[user]++;
    }

    function getNonce(address user) external view returns(uint256) {
        return nonces[user];
    }
}

abstract contract BaseGameSM {
    IEntropy public entropy;
    ITreasury public treasury;
    uint256 public houseEdge;
    uint256 public minAmount;
    address public entropyProvider;

    struct GameConfig {
        address player;
        address token;
        uint256 wager;
        bytes32 userRandomNumber;
        uint8 extra;
        uint8 count;
    }

}

contract HoneyFlipSM is BaseGameSM, IEntropyConsumer {
    mapping(uint256 => bytes) public games;
    SessionManagerSM public sessionManager;

    event GameStarted(uint64 seq, address indexed player, uint256 wager, uint8 count, address indexed token, bytes32 userRnd);
    event GameResult(address indexed player, uint256 payout, bytes32 rnd, uint8 won, uint8 played, address token);

    constructor(
        address _sessionManager,
        address _entropy,
        address _treasury,
        address _entropyProvider,
        uint256 _houseEdge,
        uint256 _minAmount
    ) {
        sessionManager = SessionManagerSM(_sessionManager);
        entropy = IEntropy(_entropy);
        treasury = ITreasury(_treasury);
        entropyProvider = _entropyProvider;
        houseEdge = _houseEdge;
        minAmount = _minAmount;
    }

    function playHoneyFlip(
        BaseGameSM.GameConfig memory config,
        bytes memory signature
    ) external {
        address user = config.player;
        require(sessionManager.isAuthorized(user, msg.sender), "Not auth");
        require(config.wager * config.count >= minAmount, "Bet too small");
        require(config.extra > 0 && config.extra < 100, "Bad prob");
        uint256 allowance = VaultTokenSM(config.token).allowance(user, address(this));
        require(allowance >= config.wager * config.count, "No allowance");

        // Проверяем подпись (пример: user, totalBet, nonce)
        bytes32 msgHash = sessionManager.getMessageHash(user, config.wager * config.count);
        bytes32 ethSignedMessageHash = sessionManager.getEthSignedMessageHash(msgHash);
        address recoveredSigner = sessionManager.recoverSigner(ethSignedMessageHash, signature);
        require(recoveredSigner == user, "Bad sig");
        sessionManager.incrementNonce(user);

        // Забираем токены у пользователя
        VaultTokenSM(config.token).transferFrom(user, address(this), config.wager * config.count);
        // Реквест рандом
        uint64 seq = entropy.requestWithCallback();
        games[seq] = abi.encode(config);
        emit GameStarted(seq, user, config.wager, config.count, config.token, config.userRandomNumber);
        treasury.notifyGameStarted(seq, user, config.wager, config.count, config.token);
    }

    function entropyCallback(uint64 seq, address, bytes32 rnd) internal override {
        BaseGameSM.GameConfig memory g = abi.decode(games[seq], (BaseGameSM.GameConfig));
        uint256 totalPayout; uint8 wonCount; uint8 played;
        for (uint8 i; i < g.count && i < 100; i++) {
            bool won = (uint256(rnd) % 100) < g.extra;
            if (won) {
                totalPayout += calcPayout(g.wager, g.extra);
                wonCount++;
            }
            played++;
            rnd >>= 2;
        }
        if (totalPayout > 0) {
            VaultTokenSM(g.token).approve(address(treasury), totalPayout);
            treasury.requestPayout(g.player, totalPayout, g.token);
        }
        emit GameResult(g.player, totalPayout, rnd, wonCount, played, g.token);
        treasury.notifyGameResult(seq, totalPayout, rnd, wonCount, played, g.extra);
    }

    function calcPayout(uint256 wager, uint8 prob) internal view returns(uint256) {
        uint256 net = (100 - houseEdge);
        return (wager * net / 100) * 100 / prob;
    }

    function getEntropy() internal view override returns(address) {
        return address(entropy);
    }
}
