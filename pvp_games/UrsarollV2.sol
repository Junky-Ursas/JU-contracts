// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@pythnetwork/entropy-sdk-solidity/IEntropy.sol";
import "@pythnetwork/entropy-sdk-solidity/IEntropyConsumer.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


// OOGA BOOGA
interface IOBRouter {
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

/// @title UrsaRollV2Proxy
/// @dev Contract for a lottery system utilizing entropy for randomness.
contract UrsaRollV2Proxy is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, IEntropyConsumer {
    using SafeERC20 for IERC20;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    /// @dev Victory fee basis points
    uint256 public victoryFee;
    /// @dev Ticket price
    uint256 public ticketPrice;
    /// @dev Maximum number of players per round
    uint256 public maxPlayers;
    /// @dev Current round index
    uint256 public currentRoundIndex;
    /// @dev Maximum number of rounds to deposit at once
    uint256 public maxRoundsToDepositATM;
    /// @dev Protocol fee recipient
    address public protocolFeeRecipient;
    /// @dev Entropy provider
    address public entropyProvider;         
    /// @dev Entropy contract
    IEntropy public entropy;               
    /// @dev Router contract
    IOBRouter public router;
    
    /// @dev Mapping of sequence numbers to round indices
    mapping(uint64 => uint256) public sequenceNumberToRoundIndex;

    /// @dev Mapping of pending refunds
    mapping(address => uint256) public pendingWithdrawals;

    struct Round {
        address winner;
        uint256 protocolFeeOwed;
        RoundStatus status;
        Deposit[] deposits;
        uint256 roundTotalTickets;
        uint64 sequenceNumber;
        uint256 currentRoundIndex;
        uint256 prizePool;
        mapping(address => bool) hasDeposited;
    }

    struct RoundDetails {
        address winner;
        uint256 protocolFeeOwed;
        RoundStatus status;
        uint256 roundTotalTickets;
        uint64 sequenceNumber;
        uint256 roundIndex;
    }

    struct Deposit {
        address depositor;
        uint256 userTotalTickets;
    }

    enum RoundStatus { 
        None, Open, Current, Drawing, Drawn, Cancelled 
    }

    mapping(uint256 => Round) rounds;

    event RoundStarted(uint256 indexed roundIndex);
    event RoundOpenedForDeposits(uint256 indexed roundIndex);
    event DepositETH(uint256 indexed roundIndex, address indexed player, uint256 amount);
    event DrawingWinner(uint256 indexed roundIndex, bytes32 userRandomNumber, uint64 indexed sequenceNumber);
    event RoundSuccess(uint256 indexed roundIndex, address indexed winner, uint256 prize, uint64 indexed sequenceNumber);
    event RoundCancelled(uint256 indexed roundIndex);
    event RoundReadyToFinish(uint256 indexed roundIndex, address indexed winner, uint256 prize, bytes32 randomNumber);
    event WagerRefunded(uint256 indexed roundIndex, address indexed player, uint256 amount);

    /// @dev Constructor for initializing the contract with entropy addresses and starting the first round.
    /// @param entropyAddress Address of the entropy contract.
    /// @param entropyProviderAddress Address of the entropy provider.
    /// @param routerAddress Address of the router contract.
    function initialize(
        address entropyAddress, 
        address entropyProviderAddress,
        address routerAddress
    ) initializer public {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        protocolFeeRecipient = msg.sender;
        entropy = IEntropy(entropyAddress);
        entropyProvider = entropyProviderAddress;
        router = IOBRouter(routerAddress); 
        currentRoundIndex = 6100;
        ticketPrice = 0.01 ether;
        victoryFee = 5000;
        maxRoundsToDepositATM = 68;
        maxPlayers = 100;
        _startNewRound();
    }

    /// @dev Starts a new round.
    function _startNewRound() internal {
        currentRoundIndex++;
        rounds[currentRoundIndex].status = RoundStatus.Current;
        rounds[currentRoundIndex].currentRoundIndex = currentRoundIndex;
        emit RoundStarted(currentRoundIndex);

        for (uint256 i = 1; i <= maxRoundsToDepositATM; i++) {
            uint256 futureRoundIndex = currentRoundIndex + i;
            if (rounds[futureRoundIndex].status == RoundStatus.None) {
                rounds[futureRoundIndex].status = RoundStatus.Open;
                rounds[futureRoundIndex].currentRoundIndex = futureRoundIndex;
                emit RoundOpenedForDeposits(futureRoundIndex);
            }
        }
    }

    /// @dev Allows a user to deposit using the native token.
    /// @param count Number of wagers to deposit.
    function playUrsaroll(uint8 count) nonReentrant external payable {
        require(count >= 1, "Zero deposits");
        require(count <= maxRoundsToDepositATM + 1, "Too many deposits");
        require(msg.value > 0, "Bet amount is below the minimum required");
        uint256 amountPerDeposit = msg.value / count;
        require(amountPerDeposit >= ticketPrice, "Bet amount is below the minimum required");
    
        for (uint256 i = 0; i < count; i++) {
            uint256 roundIndex = currentRoundIndex + i;
            Round storage round = rounds[roundIndex];
            
            if (round.status == RoundStatus.None) {
                round.status = (roundIndex == currentRoundIndex) ? RoundStatus.Current : RoundStatus.Open;
                round.currentRoundIndex = roundIndex;
                emit RoundOpenedForDeposits(roundIndex);
            }
            _deposit(msg.sender, amountPerDeposit, roundIndex);
        }
    
        uint256 totalDeposited = amountPerDeposit * count;
        uint256 leftover = msg.value - totalDeposited;
        if (leftover > 0) {
            (bool success, ) = protocolFeeRecipient.call{value: leftover}("");
            if (!success) {
                pendingWithdrawals[protocolFeeRecipient] += leftover;
            }
        }
    }


    /// @dev Allows a user to deposit multiple wagers using ERC20 tokens, swapping once and distributing the amount.
    /// @param count Number of wagers to deposit.
    /// @param tokenInfo Swap token information.
    /// @param pathDefinition Swap path definition.
    /// @param executor Address of the executor.
    /// @param referralCode Referral code.
    function playUrsarollZap(
        uint8 count,
        IOBRouter.swapTokenInfo calldata tokenInfo,
        bytes calldata pathDefinition,
        address executor,
        uint32 referralCode
    ) external payable nonReentrant {
        require(count >= 1, "Zero deposits");
        require(count <= maxRoundsToDepositATM + 1, "Too many deposits");

        require(tokenInfo.outputToken == address(0), "Output token must be native token");
        require(tokenInfo.outputReceiver == address(this), "Output receiver must be contract address");
        
        // Transfer inputToken from msg.sender to this contract
        IERC20 token = IERC20(tokenInfo.inputToken);
        bool transferSuccess = token.safeTransferFrom(msg.sender, address(this), tokenInfo.inputAmount);
        require(transferSuccess, "Transfer of input token failed");

        // Approve the router to spend the tokens
        bool approveSuccess = token.safeIncreaseAllowance(address(router), tokenInfo.inputAmount);
        require(approveSuccess, "Approve failed");

        uint256 amountOut;
        try router.swap{value: msg.value}(
            tokenInfo,
            pathDefinition,
            executor,
            referralCode
        ) returns (uint256 swapAmountOut) {
            amountOut = swapAmountOut;
        } catch {
            token.safeTransfer(msg.sender, tokenInfo.inputAmount);
            revert("Swap failed");
        }

        uint256 amountPerDeposit = amountOut / count;
        require(amountPerDeposit >= ticketPrice, "Swapped amount per deposit is below ticket price");

        for (uint256 i = 0; i < count; i++) {
            uint256 roundIndex = currentRoundIndex + i;
            Round storage round = rounds[roundIndex];
            
            if (round.status == RoundStatus.None) {
                round.status = (roundIndex == currentRoundIndex) ? RoundStatus.Current : RoundStatus.Open;
                round.currentRoundIndex = roundIndex;
                emit RoundOpenedForDeposits(roundIndex);
            }
            _deposit(msg.sender, amountPerDeposit, roundIndex);
        }

        uint256 totalDeposited = amountPerDeposit * count;
        uint256 leftover = amountOut - totalDeposited;
        if (leftover > 0) {
            (bool success, ) = protocolFeeRecipient.call{value: leftover}("");
            if (!success) {
                pendingWithdrawals[protocolFeeRecipient] += leftover;
            }
        }
    }

    /// @dev Refunds a wager for a player.
    /// @param roundIndex ID of the round.
    function refundUrsaroll(uint256 roundIndex, address payable customRecipient) external nonReentrant {
        Round storage round = rounds[roundIndex];
        require(round.status == RoundStatus.Open || round.status == RoundStatus.Current, 
            "Round not in refundable state");
        require(round.hasDeposited[msg.sender], "No wager found for player");

        uint256 wagerToRefund = 0;
        uint256 depositIndex = round.deposits.length; // Index of the deposit to remove

        // Find deposit and remember its index
        for (uint256 i = 0; i < round.deposits.length; i++) {
            if (round.deposits[i].depositor == msg.sender) {
                wagerToRefund = round.deposits[i].wager;
                round.roundTotalTickets -= round.deposits[i].userTotalTickets;
                depositIndex = i; // Save deposit index
                break;
            }
        }

        require(wagerToRefund > 0, "No wager found");
        round.hasDeposited[msg.sender] = false;

        // Remove deposit from array
        if (depositIndex < round.deposits.length - 1) {
            // If deposit is not the last, move the last deposit to its place
            round.deposits[depositIndex] = round.deposits[round.deposits.length - 1];
        }
        // Decrease array length (remove last element)
        round.deposits.pop();
        round.hasDeposited[msg.sender] = false;

        // Send funds
        (bool success, ) = customRecipient.call{value: wagerToRefund}("");
        if (!success) {
            pendingWithdrawals[customRecipient] += wagerToRefund;
        }

        emit WagerRefunded(roundIndex, msg.sender, wagerToRefund);
    }

    /// @dev Allows a player to claim their pending refund on any wallet
    /// @param customRecipient Address to send the refund to
    function claim(address payable customRecipient) external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No funds to claim");

        pendingWithdrawals[msg.sender] = 0;
        (bool success, ) = customRecipient.call{value: amount}("");
        if (!success) {
            pendingWithdrawals[msg.sender] += amount;
            revert("Claim failed: ETH transfer reverted");
        }
    }

    /// @dev Internal function to handle a deposit.
    /// @param sender Address of the sender.
    /// @param wager Amount of the wager.
    /// @param roundIndex Index of the round.
    function _deposit(address sender, uint256 wager, uint256 roundIndex) private {
        Round storage round = rounds[roundIndex];
        require(round.status == RoundStatus.Open || round.status == RoundStatus.Current, "Round is not open for deposits");
        require(round.deposits.length < maxPlayers, "Max players reached for this round");
        uint256 ticketsBought = wager / ticketPrice;
        require(ticketsBought > 0, "Wager too small");

        if (!round.hasDeposited[sender]) {
            round.roundTotalTickets += ticketsBought;
            round.deposits.push(
                Deposit({
                    depositor: sender,
                    userTotalTickets: ticketsBought
                })
            );
            round.hasDeposited[sender] = true;
        } else {
            for (uint256 i = 0; i < round.deposits.length; i++) {
                if (round.deposits[i].depositor == sender) {
                    round.deposits[i].wager += wager;
                    round.deposits[i].userTotalTickets += ticketsBought;
                    round.roundTotalTickets += ticketsBought;
                    break;
                }
            }
        }

        emit DepositETH(roundIndex, sender, wager);
    }

    /// @dev Requests entropy and initiates the process of selecting a winner.
    /// @param userRandomNumber A random number provided for the entropy request.
    function drawWinnerUrsaroll(bytes32 userRandomNumber) external payable onlyOwner {
        Round storage round = rounds[currentRoundIndex];
        uint256 fee = entropy.getFee(entropyProvider);
        require(msg.value >= fee, "Insufficient fee");
        require(round.deposits.length > 1, "Not enough players");
        require(round.status == RoundStatus.Current || round.status == RoundStatus.Drawing, "Round is not current");

        uint64 sequenceNumber = entropy.requestWithCallback{value: fee}(entropyProvider, userRandomNumber);
        sequenceNumberToRoundIndex[sequenceNumber] = currentRoundIndex;
        round.sequenceNumber = sequenceNumber;
        round.status = RoundStatus.Drawing;
        emit DrawingWinner(currentRoundIndex, userRandomNumber, sequenceNumber);
    }

    /// @dev Callback function to handle the result of the entropy request.
    /// @param sequenceNumber Sequence number of the entropy request.
    /// @param randomNumber The generated random number.
    function entropyCallback(uint64 sequenceNumber, address, bytes32 randomNumber) internal override {
        uint256 roundIndex = sequenceNumberToRoundIndex[sequenceNumber];
        Round storage round = rounds[roundIndex];
        require(round.status == RoundStatus.Drawing, "Round is not drawing");

        round.winner = findTicket(round, uint256(randomNumber) % round.roundTotalTickets + 1);
        round.prizePool = round.roundTotalTickets * ticketPrice;
        round.status = RoundStatus.Drawn;
        emit RoundReadyToFinish(roundIndex, round.winner, round.prizePool, randomNumber);
    }

    /// @dev Finishes the current round.
    function finishUrsarollRound() external nonReentrant onlyOwner {
        Round storage round = rounds[currentRoundIndex];
        require(round.status == RoundStatus.Drawn, "Round not ready to be finished");
        require(round.winner != address(0), "Winner not determined");
        
        uint256 prize = round.prizePool;
        uint256 fee = prize * victoryFee / 100000;
        
        _distributeFees(fee);
        
        (bool success, ) = round.winner.call{value: prize - fee}("");
        if (!success) {
            pendingWithdrawals[round.winner] += prize - fee;
        }
        
        emit RoundSuccess(currentRoundIndex, round.winner, prize, round.sequenceNumber);
        
        _startNewRound();
    }

    /// @dev Finds the ticket that corresponds to the winning index.
    /// @param winningTicket Index of the winning ticket.
    /// @param round Round object.
    /// @return winner Address of the winner.
    function findTicket(Round storage round, uint256 winningTicket) internal view returns (address winner) {
        uint256 cumulativeTickets = 0;
        for (uint16 i = 0; i < round.deposits.length; i++) {
            cumulativeTickets += round.deposits[i].userTotalTickets;
            if (cumulativeTickets >= winningTicket) {
                return round.deposits[i].depositor;
            }
        }
        revert("Winner not found");
    }

    /// @dev Cancels a round.
    /// @param roundIndex ID of the round to be cancelled.
    function cancelRound(uint256 roundIndex) external onlyOwner {
        Round storage round = rounds[roundIndex];
        require(round.status == RoundStatus.Open || round.status == RoundStatus.Current || round.status == RoundStatus.Drawing, 
            "Cannot cancel at this stage");
        
        round.status = RoundStatus.Cancelled;

        for (uint256 i = 0; i < round.deposits.length; i++) {
            address depositor = round.deposits[i].depositor;
            uint256 wager = round.deposits[i].wager;
            
            (bool success, ) = depositor.call{value: wager}("");
            if (!success) {
                pendingWithdrawals[depositor] += wager;
            }
        }

        emit RoundCancelled(roundIndex);
    }

    /// @dev Updates the value per ticket.
    /// @param newPrice New value for the ticket.
    function setTicketPrice(uint256 newPrice) external onlyOwner {
        ticketPrice = newPrice;
    }

    /// @dev Updates the maximum number of players per round.
    /// @param newMaxPlayers New maximum number of players.
    function setMaxPlayers(uint256 newMaxPlayers) external onlyOwner {
        maxPlayers = newMaxPlayers;
    }

    /// @dev Updates the protocol fee basis points.
    /// @param newFee New protocol fee basis points.
    function setVictoryFee(uint256 newFee) external onlyOwner {
        victoryFee = newFee;
    }

    /// @dev Updates the entropy contract address.
    /// @param _entropy New entropy contract address.
    function setNewEntropy(address _entropy) external onlyOwner {
        entropy = IEntropy(_entropy);
    }

    /// @dev Distributes fees to the fee recipient.
    /// @param amount Amount to distribute.
    function _distributeFees(uint256 amount) internal {
        (bool success, ) = protocolFeeRecipient.call{value: amount}("");
        if (!success) {
            pendingWithdrawals[protocolFeeRecipient] += amount;
        }
    }

    /// @dev Returns the address of the entropy contract.
    function getEntropy() internal view override returns (address) {
        return address(entropy);
    }

    /// @dev Retrieves details of a specific round.
    /// @param roundIndex ID of the round to retrieve.
    /// @return details Struct containing all round details.
    function getRound(uint256 roundIndex) external view returns (RoundDetails memory details) {
        Round storage round = rounds[roundIndex];
        return RoundDetails(
            round.winner,
            round.protocolFeeOwed,
            round.status,
            round.roundTotalTickets,
            round.sequenceNumber,
            round.currentRoundIndex
        );
    }

    /// @dev Retrieves details of a current round.
    /// @return details Struct containing all round details.
    function getCurrentRound() external view returns (RoundDetails memory details) {
        Round storage round = rounds[currentRoundIndex];
        return RoundDetails(
            round.winner,
            round.protocolFeeOwed,
            round.status,
            round.roundTotalTickets,
            round.sequenceNumber,
            round.currentRoundIndex
        );
    }

    
    /// @dev Updates the current round index.
    /// @param newIndex New index for the current round.
    function updateCurrentRoundIndex(uint256 newIndex) external onlyOwner {
        currentRoundIndex = newIndex;
    }

    /// @dev Retrieves all deposits by current round.
    /// @return depositors Array of all depositors.
    /// @return userTotalTickets Array of all userTotalTickets.
    function getDepositsForCurrentRound() external view returns (
        address[] memory depositors,
        uint256[] memory userTotalTickets
    ) {
        Round storage round = rounds[currentRoundIndex];
        uint256 numDeposits = round.deposits.length;

        depositors = new address[](numDeposits);
        userTotalTickets = new uint256[](numDeposits);

        for (uint256 i = 0; i < numDeposits; i++) {
            Deposit storage _currentDeposit = round.deposits[i];
            depositors[i] = _currentDeposit.depositor;
            userTotalTickets[i] = _currentDeposit.userTotalTickets;
        }
    }

        /// @dev Retrieves deposits by round.
    /// @param roundIndex ID of the round.
    /// @return depositors Array of all depositors.
    /// @return userTotalTickets Array of all userTotalTickets.
    function getDepositsForRound(uint256 roundIndex) external view returns (
        address[] memory depositors,
        uint256[] memory userTotalTickets
    ) {
        Round storage round = rounds[roundIndex];
        uint256 numDeposits = round.deposits.length;

        depositors = new address[](numDeposits);
        userTotalTickets = new uint256[](numDeposits);

        for (uint256 i = 0; i < numDeposits; i++) {
            Deposit storage _currentDeposit = round.deposits[i];
            depositors[i] = _currentDeposit.depositor;
            userTotalTickets[i] = _currentDeposit.userTotalTickets;
        }
    }

    /// @dev Retrieves a specific deposit by round and deposit index.
    /// @param roundIndex ID of the round.
    /// @param depositIndex Index of the deposit within the round.
    /// @return userDeposit Details of the specified deposit.
    function getDeposit(uint256 roundIndex, uint256 depositIndex) external view returns (Deposit memory userDeposit) {
        Round storage round = rounds[roundIndex];
        require(depositIndex < round.deposits.length, "Deposit index out of bounds");
        return round.deposits[depositIndex];
    }

    function setProtocolFeeRecipient(address newProtocolFeeRecipient) external onlyOwner {
        protocolFeeRecipient = newProtocolFeeRecipient;
    }

    function setMaxRoundsToDepositATM(uint256 newMaxRoundsToDepositATM) external onlyOwner {
        maxRoundsToDepositATM = newMaxRoundsToDepositATM;
    }

    function setRouter(address newRouter) external onlyOwner {
        router = IOBRouter(newRouter);
    }

    /// @dev Fallback function to receive native tokens.
    receive() external payable {}

    
}