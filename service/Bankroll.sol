// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libs/JunkyUrsasEventsLib.sol";

/// @title Bankroll
/// @dev Manages deposits, payouts, and liquidity for whitelisted entities.
contract Bankroll is JunkyUrsasEventsLib {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    mapping(address => bool) internal whitelistedEntities;
    mapping(address => bool) internal blacklistedEntities;
    mapping(address => uint256) internal tokenBalances;
    mapping(address => bool) internal whitelistedTokens;
    bool internal withdrawalsFrozen;

    address internal protocolFeeRecipient;
    uint256 internal protocolFeePercentage;

    /// @dev Modifier to restrict actions to only whitelisted entities.
    /// @param entity Address of the entity to check.
    modifier WhitelistedEntity(address entity) {
        require(whitelistedEntities[entity], "Not a whitelisted entity");
        _;
    }

    /// @dev Modifier to ensure the entity is not blacklisted.
    /// @param entity Address of the entity to check.
    modifier NotBlacklistedEntity(address entity) {
        require(!blacklistedEntities[entity], "Blacklisted");
        _;
    }

    /// @dev Modifier to ensure the token is whitelisted.
    /// @param token Address of the token to check.
    modifier WhitelistedToken(address token) {
        require(whitelistedTokens[token], "Token not whitelisted");
        _;
    }

    /// @dev Modifier to check if withdrawals are frozen.
    modifier WhenNotFrozen() {
        require(!withdrawalsFrozen, "Withdrawals are frozen");
        _;
    }

    /// @dev Initializes the contract with the owner and reentrancy guard.
    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        protocolFeePercentage = 100; // 1%
        protocolFeeRecipient = msg.sender;
    }

    /// @dev Allows a whitelisted entity to deposit ETH.
    /// @param amount Amount of ETH to deposit.
    function depositETH(address from, uint256 amount) external payable nonReentrant WhitelistedEntity(msg.sender) NotBlacklistedEntity(msg.sender) {
        require(msg.value >= amount, "Invalid ETH amount");
        tokenBalances[address(0)] += msg.value;
        emit DepositETH(from, amount);
    }

    /// @dev Allows a whitelisted entity to transfer ERC20 tokens to bankroll.
    /// @param token Address of the token.
    /// @param from Address to transfer from.
    /// @param amount Amount to transfer.
    function depositERC20(address token, address from, uint256 amount) external 
        nonReentrant 
        WhitelistedToken(token) 
        WhitelistedEntity(msg.sender) 
        NotBlacklistedEntity(from)
        NotBlacklistedEntity(msg.sender) 
    {
        require(IERC20(token).transferFrom(from, address(this), amount), "Transfer failed");
        tokenBalances[token] += amount;
        emit DepositERC20(from, amount, token);
    }

    /// @dev Allows the owner to set the fee recipient address.
    /// @param newProtocolFeeRecipient Address of the fee recipient.
    function setProtocolFeeRecipient(address newProtocolFeeRecipient) external onlyOwner {
        protocolFeeRecipient = newProtocolFeeRecipient;
        emit ProtocolFeeRecipientSet(newProtocolFeeRecipient);
    }

    /// @dev Allows the owner to set the fee percentage.
    /// @param newProtocolFeePercentage New fee percentage (in basis points, e.g., 100 = 1%).
    function setProtocolFeePercentage(uint256 newProtocolFeePercentage) external onlyOwner {
        require(newProtocolFeePercentage <= 10000, "Fee percentage too high");
        protocolFeePercentage = newProtocolFeePercentage;
        emit ProtocolFeePercentageSet(newProtocolFeePercentage);
    }

    /// @dev Allows a whitelisted entity to request a payout.
    /// @param user Address of the user to pay out.
    /// @param amount Amount to pay out.
    /// @param token Address of the token to pay out.
    function requestPayoutFromBankroll(address user, uint256 amount, address token) external 
        WhitelistedEntity(msg.sender)
        nonReentrant 
        NotBlacklistedEntity(user)
        WhenNotFrozen 
    {
        require(tokenBalances[token] >= amount, "Insufficient balance");

        uint256 fee = (amount * protocolFeePercentage) / 10000; 
        uint256 payoutAmount = amount - fee; 

        tokenBalances[token] -= amount;

        if (token == address(0)) {
            payable(protocolFeeRecipient).transfer(fee);
            payable(user).transfer(payoutAmount);
        } else {
            require(IERC20(token).transfer(protocolFeeRecipient, fee), "Fee transfer failed");
            require(IERC20(token).transfer(user, payoutAmount), "Payout transfer failed");
        }

        emit Payout(user, payoutAmount, token);
    }

    /// @dev Emits an event to notify that a global game has started.
    /// @param config Game configuration.
    /// @param sequenceNumber Sequence number of the game.
    /// @param gameAddress Address of the game contract.
    /// @param timestamp Timestamp of the game start.
    function notifyGameStarted(
        GameConfig memory config,
        uint64 sequenceNumber,
        address gameAddress,
        uint256 timestamp
    ) external WhitelistedEntity(msg.sender) {
        emit GlobalGameStarted(config, sequenceNumber, gameAddress, timestamp);
    }

    /// @dev Emits an event to notify the result of a global game.
    /// @dev GameConfig memory config, Flags memory flags, uint256 totalPayout, uint64 sequenceNumber, address gameAddress, uint256 timestamp
    /// @param config Game configuration.
    /// @param flags Game flags.
    /// @param totalPayout Total payout amount.
    /// @param sequenceNumber Sequence number of the game.
    /// @param gameAddress Address of the game contract.
    /// @param timestamp Timestamp of the game start.
    function notifyGameResult(
        GameConfig memory config,
        Flags memory flags,
        uint256 totalPayout,
        uint64 sequenceNumber,
        address gameAddress,
        uint256 timestamp
    ) external WhitelistedEntity(msg.sender) {
        emit GlobalGameResult(config, flags, totalPayout, sequenceNumber, gameAddress, timestamp);
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
    ) external WhitelistedEntity(msg.sender) {
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
    ) external WhitelistedEntity(msg.sender) {
        emit VMLiquidityRemoved(user, liqTokenAddress, liqTokenAmount, vaultTokenAmount);
    }

    /// @dev Emits an event to notify vault creation.
    /// @param liqTokenAddress Address of the liquidity token.
    /// @param vaultTokenAddress Address of the vault token.
    function notifyVaultCreated(
        address liqTokenAddress,
        address vaultTokenAddress
    ) external WhitelistedEntity(msg.sender) {
        emit VMVaultCreated(liqTokenAddress, vaultTokenAddress);
    }

    /// @dev Blacklists an address.
    /// @param user Address to blacklist.
    function blacklistAddress(address user) external onlyOwner {
        blacklistedEntities[user] = true;
        emit EntityAddedToBlacklist(user);
    }

    /// @dev Whitelists an entity.
    /// @param entity Address of the entity.
    function whitelistEntity(address entity) external onlyOwner {
        whitelistedEntities[entity] = true;
        emit EntityAddedToWhitelist(entity);
    }

    /// @dev Removes an address from the blacklist.
    /// @param user Address to remove from blacklist.
    function removeEntityFromBlacklist(address user) external onlyOwner {
        blacklistedEntities[user] = false;
        emit RemovedFromBlacklist(user);
    }

    /// @dev Removes an entity from the whitelist.
    /// @param entity Address of the entity.
    function removeEntityFromWhitelist(address entity) external onlyOwner {
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
    /// @return tokenBalance The balance of the token.
    function getBalance(address token) external view returns (uint256 tokenBalance) {
        return tokenBalances[token];
    }

    /// @dev Checks the status of an account (whitelisted/blacklisted)
    /// @param account Address to check
    /// @return isWhitelisted Whether the account is whitelisted
    /// @return isBlacklisted Whether the account is blacklisted
    function checkAccountStatus(address account) external view returns (
        bool isWhitelisted,
        bool isBlacklisted
    ) {
        return (
            whitelistedEntities[account],
            blacklistedEntities[account]
        );
    }
}
