// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./JunkyUrsasStructsLib.sol";

abstract contract JunkyUrsasEventsLib is JunkyUrsasStructsLib {
    event GameStarted(
        GameConfig config, 
        uint64 sequenceNumber
    );

    /// @dev Emitted when a game result is processed.
    event GameResult(
        GameConfig config,
        Flags flags,
        uint256 totalPayout,
        uint64 sequenceNumber
    );

    event GameCanceledAndRefunded(
        GameConfig config,
        uint64 sequenceNumber
    );

    event EmergencyWithdraw(
        address token,
        uint256 amount
    );

    event EntropyProviderSet(
        address newEntropyProvider
    );

    event EntropySet(
        address newEntropy
    );

    event BankrollSet(
        address newBankroll
    );

    event MaxIterationsSet(
        uint8 newMaxIterations
    );

    event MinBetAmountSet(
        uint256 newMinBetAmount
    );

    event HouseEdgeSet(
        uint8 newHouseEdge
    );

    event MaxWinPercentageSet(
        uint256 newMaxWinPercentage
    );

    event BlinkoMultipliersSet(
        uint8 mode,
        uint256[13] newMultipliers
    );

    event BlinkoLevelsCountSet(
        uint8 newLevelsCount
    );

    event BlinkoHolesCountSet(
        uint8 newHolesCount
    );

    event HoneyFlipMaxProbabilitySet(
        uint8 newMaxProbability
    );

    event HoneyFlipMinProbabilitySet(
        uint8 newMinProbability
    );

    event JunkySlotsV2MultipliersSet(
        uint16[13] newMultipliers
    );

    event JunkySlotsV2SpecialMultipliersSet(
        uint16[3] newSpecialMultipliers
    );

    event JunkySlotsSuperMultipliersSet(
        uint16[18] newMultipliers
    );

    event JunkySlotsSuperReelsSet(
        uint16[16][3] newReels
    );

    event JunkySlotsSuperSpecialConfigSet(
        SlotsSpecialConfig newConfig
    );

    event DepositETH(
        address indexed user, 
        uint256 amount
    );

    event DepositERC20(
        address indexed user,
        uint256 amount,
        address indexed token
    );

    event Payout(
        address indexed user, 
        uint256 amount, 
        address indexed token
    );

    event EntityAddedToBlacklist(
        address indexed entity
    );

    event EntityAddedToWhitelist(
        address indexed entity
    );

    event RemovedFromBlacklist(
        address indexed entity
    );

    event RemovedFromWhitelist(
        address indexed entity
    );

    event TokenWhitelisted(
        address indexed token
    );

    event TokenRemovedFromWhitelist(
        address indexed token
    );

    event WithdrawalsFrozen();

    event WithdrawalsUnfrozen();

    event VMLiquidityAdded(
        address indexed userAddress,
        address indexed liqTokenAddress,
        uint256 liqTokenAmount,
        uint256 vaultTokensAmount
    );

    event VMLiquidityRemoved(
        address indexed userAddress,
        address indexed liqTokenAddress,
        uint256 liqTokenAmount,
        uint256 vaultTokensAmount
    );

    event VMVaultCreated(
        address indexed vaultTokenAddress,
        address indexed liqTokenAddress
    );

    event GlobalGameStarted(
        GameConfig config,
        uint64 sequenceNumber,
        address gameAddress,
        uint256 timestamp
    );

    event GlobalGameResult(
        GameConfig config,
        Flags flags,
        uint256 totalPayout,
        uint64 sequenceNumber,
        address gameAddress,
        uint256 timestamp
    );

    event ProtocolFeeRecipientSet(
        address newProtocolFeeRecipient
    );

    event ProtocolFeePercentageSet(
        uint256 newProtocolFeePercentage
    );

    /// @dev Event to notify when vault is created
    /// @param liqTokenAddress The address of the liquidity token
    /// @param vaultTokenAddress The address of the vault token
    event VaultCreated(
        address indexed liqTokenAddress,
        address indexed vaultTokenAddress
    );
    /// @dev Event to notify when liquidity is added
    /// @param user The address of the user
    /// @param liqTokenAddress The address of the liquidity token
    /// @param amount The amount of liquidity added
    /// @param vaultTokens The amount of vault tokens added
    event LiquidityAdded(
        address indexed user,
        address indexed liqTokenAddress,
        uint256 amount,
        uint256 vaultTokens
    );
    /// @dev Event to notify when liquidity is removed
    /// @param user The address of the user
    /// @param liqTokenAddress The address of the liquidity token
    /// @param amount The amount of liquidity removed
    /// @param vaultTokens The amount of vault tokens removed
    event LiquidityRemoved(
        address indexed user,
        address indexed liqTokenAddress,
        uint256 amount,
        uint256 vaultTokens
    );

    /// @dev Event to notify when vault token transfer
    /// @param from The address of the sender
    /// @param to The address of the receiver
    /// @param liqToken The address of the liquidity token
    /// @param vaultTokens The amount of vault tokens transferred
    /// @param initialAmount The initial amount transferred
    event VaultTokenTransferred(
        address indexed from,
        address indexed to,
        address indexed liqToken,
        uint256 vaultTokens,
        uint256 initialAmount
    );

    /// @dev Event to notify when staking contract is added
    /// @param stakingContract The address of the staking contract
    event StakingContractAdded(address indexed stakingContract);

    /// @dev Event to notify when staking contract is removed
    /// @param stakingContract The address of the staking contract
    event StakingContractRemoved(address indexed stakingContract);

    /// @dev Event to notify when vault token is staked
    /// @param from The address of the user
    /// @param stakingContract The address of the staking contract
    /// @param liqToken The address of the liquidity token
    /// @param vaultTokens The amount of vault tokens staked
    /// @param stakedAmount The amount of liquidity staked
    event VaultTokenStaked(
        address indexed from,
        address indexed stakingContract,
        address indexed liqToken,
        uint256 vaultTokens,
        uint256 stakedAmount
    );

    event VaultTokenUnstaked(
        address indexed from,
        address indexed to,
        address indexed liqToken,
        uint256 vaultTokens
    );
}