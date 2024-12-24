// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

/// @title TreasuryContract
/// @notice Manages deposits, payouts and liquidity for the gaming platform
/// @dev Handles token deposits/withdrawals and maintains whitelisted entities
contract TreasuryContractProxy is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    /// @notice Mapping of whitelisted game contracts
    mapping(address => bool) public whitelistedEntities;
    /// @notice Mapping of blacklisted player addresses
    mapping(address => bool) public blacklistedAddresses;
    /// @notice Token balances for each token type
    mapping(address => uint256) public tokenBalances;
    /// @notice Mapping of whitelisted tokens accepted by treasury
    mapping(address => bool) public whitelistedTokens;
    uint256 public houseEdge;
    bool public withdrawalsFrozen;

    address public feeRecipient;  
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
    event BlacklistedEntity(address indexed user);
    event WhitelistedEntity(address indexed entity);
    event RemovedFromBlacklist(address indexed user);
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

    /// @dev Modifier to ensure the user is not blacklisted.
    /// @param user Address of the user to check.
    modifier notBlacklisted(address user) {
        require(!blacklistedAddresses[user], "Blacklisted");
        _;
    }

    /// @dev Modifier to ensure the token is whitelisted.
    /// @param token Address of the token to check.
    modifier onlyWhitelistedTokens(address token) {
        require(whitelistedTokens[token], "Token not whitelisted");
        _;
    }

    /// @dev Initializes the contract with the owner and reentrancy guard.
    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

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
        require(IERC20(token).transferFrom(from, to, amount), "Transfer failed");
        tokenBalances[token] += amount;
        emit Deposit(msg.sender, amount, token);
    }

/// @dev Allows the owner to set the fee recipient address.
    /// @param _feeRecipient Address of the fee recipient.
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
    }

    /// @dev Allows the owner to set the fee percentage.
    /// @param _feePercentage New fee percentage (in basis points, e.g., 100 = 1%).
    function setFeePercentage(uint256 _feePercentage) external onlyOwner {
        require(_feePercentage <= 10000, "Fee percentage too high");
        feePercentage = _feePercentage;
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
            require(IERC20(token).transfer(feeRecipient, fee), "Fee transfer failed");
            require(IERC20(token).transfer(user, payoutAmount), "Payout transfer failed");
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

    /// @dev Emits an event to notify liquidity added.
    /// @param user Address of the user.
    /// @param liqTokenAddress Address of the liquidity token.
    /// @param liqTokenAmount Amount of liquidity token.
    /// @param vaultTokenAmount Amount of vault token.
    function notifyLiquidityAdded(
        address user,
        address liqTokenAddress,
        uint256 liqTokenAmount,
        uint256 vaultTokenAmount
    ) external onlyWhitelistedEntities {
        emit VMLiquidityAdded(user, liqTokenAddress, liqTokenAmount, vaultTokenAmount);
    }

    /// @dev Emits an event to notify liquidity removed.
    /// @param user Address of the user.
    /// @param liqTokenAddress Address of the liquidity token.
    /// @param liqTokenAmount Amount of liquidity token.
    /// @param vaultTokenAmount Amount of vault token.
    function notifyLiquidityRemoved(
        address user,
        address liqTokenAddress,
        uint256 liqTokenAmount,
        uint256 vaultTokenAmount
    ) external onlyWhitelistedEntities {
        emit VMLiquidityRemoved(user, liqTokenAddress, liqTokenAmount, vaultTokenAmount);
    }

    /// @dev Emits an event to notify vault creation.
    /// @param liqTokenAddress Address of the liquidity token.
    /// @param vaultTokenAddress Address of the vault token.
    function notifyVaultCreated(
        address liqTokenAddress,
        address vaultTokenAddress
    ) external onlyWhitelistedEntities {
        emit VMVaultCreated(liqTokenAddress, vaultTokenAddress);
    }

    /// @dev Sets the house edge.
    /// @param newEdge New house edge value.
    function setHouseEdge(uint256 newEdge) external onlyOwner {
        houseEdge = newEdge;
    }

    /// @dev Blacklists an address.
    /// @param user Address to blacklist.
    function blacklistAddress(address user) external onlyOwner {
        blacklistedAddresses[user] = true;
        emit BlacklistedEntity(user);
    }

    /// @dev Whitelists an entity.
    /// @param entity Address of the entity.
    function whitelistEntity(address entity) external onlyOwner {
        whitelistedEntities[entity] = true;
        emit WhitelistedEntity(entity);
    }

    /// @dev Removes an address from the blacklist.
    /// @param user Address to remove from blacklist.
    function removeFromBlacklist(address user) external onlyOwner {
        blacklistedAddresses[user] = false;
        emit RemovedFromBlacklist(user);
    }

    /// @dev Removes an entity from the whitelist.
    /// @param entity Address of the entity.
    function removeFromWhitelist(address entity) external onlyOwner {
        whitelistedEntities[entity] = false;
        emit RemovedFromWhitelist(entity);
    }

    /// @dev Whitelists a token.
    /// @param token Address of the token.
    function whitelistToken(address token) external onlyOwner {
        whitelistedTokens[token] = true;
        emit TokenWhitelisted(token);
    }

    /// @dev Removes a token from the whitelist.
    /// @param token Address of the token.
    function removeTokenFromWhitelist(address token) external onlyOwner {
        whitelistedTokens[token] = false;
        emit TokenRemovedFromWhitelist(token);
    }

    /// @dev Freezes withdrawals.
    function freezeWithdrawals() external onlyOwner {
        withdrawalsFrozen = true;
        emit WithdrawalsFrozen();
    }

    /// @dev Unfreezes withdrawals.
    function unfreezeWithdrawals() external onlyOwner {
        withdrawalsFrozen = false;
        emit WithdrawalsUnfrozen();
    }

    /// @dev Retrieves the balance of a specific token.
    /// @param token Address of the token.
    /// @return The balance of the token.
    function getBalance(address token) external view returns (uint256) {
        return tokenBalances[token];
    }
}
