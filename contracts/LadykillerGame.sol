// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {FixedVRFConsumerBaseV2Plus} from "./FixedVRFConsumerBaseV2Plus.sol";

/// @title Ladykiller on-chain chase game
/// @notice Manages one active round at a time, one Chainlink VRF request per funded round,
///         pooled solvency, settlement, claims, timeout cancellation and refunds.
/// @dev This is an initial implementation and must be audited before mainnet use.
contract LadykillerGame is FixedVRFConsumerBaseV2Plus, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint8 public constant MALE_COUNT = 51;
    uint8 public constant SUCCESSFUL_MALE_COUNT = 3;
    uint8 public constant RESULT_COUNT = 49;
    uint8 public constant RULES_VERSION = 3;
    uint40 public constant BETTING_DURATION = 45 seconds;
    uint40 public constant VRF_FINAL_TIMEOUT = 24 hours;
    uint32 public constant NUM_RANDOM_WORDS = 1;
    uint256 public constant BET_OPTION_COUNT = 12;
    uint256 public constant MAX_BETS_PER_TRANSACTION = BET_OPTION_COUNT;
    uint256 public constant MAX_CLAIMS_PER_TRANSACTION = 50;
    uint256 public constant MAX_REFUNDS_PER_TRANSACTION = 50;
    uint256 public constant MAX_PLAYER_ROUNDS_PAGE = 100;

    enum RoundState {
        NONE,
        BETTING,
        WAITING_RANDOMNESS,
        RANDOM_READY,
        SETTLED,
        CANCELLED,
        SKIPPED
    }

    enum BetOption {
        RANGE_1_5,
        RANGE_6_10,
        RANGE_11_15,
        RANGE_16_20,
        RANGE_21_25,
        RANGE_26_30,
        RANGE_31_35,
        RANGE_36_40,
        RANGE_41_45,
        RANGE_46_49,
        DAY,
        NIGHT
    }

    struct BetInput {
        BetOption option;
        uint256 amount;
    }

    struct Round {
        RoundState state;
        uint8 rulesVersion;
        uint8[3] successfulMaleIds;
        uint8 resultPosition;
        uint8 winningMaleId;
        uint40 createdAt;
        uint40 bettingStart;
        uint40 bettingDeadline;
        uint40 randomnessRequestedAt;
        uint256 randomWord;
        uint256 totalBets;
        uint256 requiredReserve;
        uint256 totalPayout;
    }

    struct RequestInfo {
        uint256 roundId;
        bool fulfilled;
    }

    error UnauthorizedKeeper();
    error InvalidAddress();
    error InvalidAmount();
    error BelowMinimumBet(uint256 minimum, uint256 provided);
    error InvalidTokenDecimals(uint8 decimals);
    error InvalidDayBetPrecision();
    error InvalidState(RoundState expected, RoundState actual);
    error BettingClosed();
    error BettingStillOpen();
    error TooManyBets();
    error TooManyClaims();
    error InvalidRefundBatchSize();
    error RefundNotDeferred();
    error InsufficientBankroll(uint256 required, uint256 available);
    error UnsupportedFeeOnTransferToken();
    error NothingToClaim();
    error AlreadyClaimed();
    error TimeoutNotReached();
    error RequestWindowExpired();
    error RandomnessAlreadyAvailable();
    error InvalidVrfConfiguration();
    error ActiveRoundExists(uint256 roundId);
    error EmptyRound();
    error RoundHasBets();

    IERC20 public immutable wagerToken;
    uint256 public immutable minimumBet;
    bytes32 public immutable vrfKeyHash;
    uint256 public immutable vrfSubscriptionId;
    uint32 public immutable vrfCallbackGasLimit;
    uint16 public immutable vrfRequestConfirmations;
    uint40 public immutable vrfTimeout;
    bool public immutable payVrfWithNative;

    uint256 public nextRoundId = 1;
    uint256 public activeRoundId;
    uint256 public totalActiveReserve;
    uint256 public lockedPlayerPayouts;
    uint256 public safetyBuffer;

    uint256 public keeperEpoch = 1;
    mapping(address => uint256) private _keeperEpoch;
    mapping(uint256 => Round) private _rounds;
    mapping(uint256 => RequestInfo) public vrfRequests;

    mapping(uint256 => mapping(address => mapping(BetOption => uint256))) private _bets;
    mapping(uint256 => mapping(address => uint256)) public totalBetByPlayer;
    mapping(uint256 => mapping(address => bool)) public claimed;
    mapping(uint256 => mapping(address => bool)) public refunded;
    mapping(uint256 => mapping(address => bool)) public refundDeferred;
    mapping(uint256 => uint256) public refundCursor;
    mapping(address => uint256[]) private _playerRounds;
    mapping(uint256 => address[]) private _roundPlayers;

    mapping(uint256 => mapping(BetOption => uint256)) public optionBetTotals;

    event KeeperUpdated(address indexed keeper, bool allowed);
    event SafetyBufferUpdated(uint256 oldBuffer, uint256 newBuffer);
    event BankrollFunded(address indexed funder, uint256 amount);
    event FreeFundsWithdrawn(address indexed recipient, uint256 amount);
    event RoundStarted(uint256 indexed roundId, uint40 bettingStart, uint40 bettingDeadline);
    event BetSelectionPlaced(
        address indexed player,
        uint256 indexed roundId,
        BetOption option,
        uint256 amount
    );
    event BetsPlaced(address indexed player, uint256 indexed roundId, uint256 amount, uint256 newReserve);
    event RoundClosed(uint256 indexed roundId, uint256 indexed requestId);
    event RoundSkipped(uint256 indexed roundId);
    event ResultRandomnessReady(uint256 indexed roundId, uint256 indexed requestId, uint256 randomWord);
    event RoundSettled(
        uint256 indexed roundId,
        uint8 resultPosition,
        uint8 winningMaleId,
        uint8[3] successfulMaleIds,
        uint256 totalPayout
    );
    event Claimed(address indexed player, uint256 indexed roundId, uint256 amount);
    event RoundCancelled(uint256 indexed roundId, uint256 refundLiability);
    event StalledRoundReleased(uint256 indexed roundId);
    event Refunded(address indexed player, uint256 indexed roundId, uint256 amount);
    event RefundDeferred(address indexed player, uint256 indexed roundId, uint256 amount);
    event RandomnessFulfillmentIgnored(uint256 indexed requestId, uint256 indexed roundId);

    modifier onlyKeeper() {
        if (!keepers(msg.sender) && msg.sender != owner()) revert UnauthorizedKeeper();
        _;
    }

    constructor(
        address wagerTokenAddress,
        address vrfCoordinator,
        bytes32 keyHash,
        uint256 subscriptionId,
        uint32 callbackGasLimit,
        uint16 requestConfirmations,
        uint40 timeout,
        bool nativePayment,
        uint256 initialSafetyBuffer,
        address initialKeeper
    ) FixedVRFConsumerBaseV2Plus(vrfCoordinator) {
        if (
            wagerTokenAddress == address(0) || vrfCoordinator == address(0)
                || initialKeeper == address(0) || initialKeeper == msg.sender
        ) revert InvalidAddress();
        if (callbackGasLimit == 0 || requestConfirmations == 0 || timeout == 0) {
            revert InvalidVrfConfiguration();
        }

        wagerToken = IERC20(wagerTokenAddress);
        uint8 tokenDecimals = IERC20Metadata(wagerTokenAddress).decimals();
        if (tokenDecimals > 77) revert InvalidTokenDecimals(tokenDecimals);
        minimumBet = 10 ** uint256(tokenDecimals);
        vrfKeyHash = keyHash;
        vrfSubscriptionId = subscriptionId;
        vrfCallbackGasLimit = callbackGasLimit;
        vrfRequestConfirmations = requestConfirmations;
        vrfTimeout = timeout;
        payVrfWithNative = nativePayment;
        safetyBuffer = initialSafetyBuffer;
        _keeperEpoch[initialKeeper] = keeperEpoch;
        emit KeeperUpdated(initialKeeper, true);
    }

    /// @notice Creates a round and immediately opens its fixed betting window.
    /// @dev No randomness is requested until betting has closed.
    function startRound() external onlyKeeper whenNotPaused returns (uint256 roundId) {
        if (activeRoundId != 0) revert ActiveRoundExists(activeRoundId);
        roundId = nextRoundId++;
        activeRoundId = roundId;
        Round storage round = _rounds[roundId];
        uint40 bettingStart = uint40(block.timestamp);
        uint40 bettingDeadline = uint40(block.timestamp + BETTING_DURATION);

        round.state = RoundState.BETTING;
        round.rulesVersion = RULES_VERSION;
        round.createdAt = bettingStart;
        round.bettingStart = bettingStart;
        round.bettingDeadline = bettingDeadline;

        emit RoundStarted(roundId, bettingStart, bettingDeadline);
    }

    /// @notice Places one or more range/day/night bets with independent amounts in one transaction.
    function placeBets(uint256 roundId, BetInput[] calldata inputs) external nonReentrant whenNotPaused {
        Round storage round = _rounds[roundId];
        if (round.state != RoundState.BETTING) revert InvalidState(RoundState.BETTING, round.state);
        if (block.timestamp >= round.bettingDeadline) revert BettingClosed();
        if (inputs.length == 0 || inputs.length > MAX_BETS_PER_TRANSACTION) revert TooManyBets();

        uint256 totalAmount;
        for (uint256 i; i < inputs.length; ++i) {
            BetInput calldata input = inputs[i];
            if (input.amount < minimumBet) revert BelowMinimumBet(minimumBet, input.amount);
            if (input.option == BetOption.DAY) {
                // Ensures aggregate 1.9x liability exactly equals the sum of
                // per-player claims, leaving no permanently locked rounding dust.
                if (input.amount % 10 != 0) revert InvalidDayBetPrecision();
            }
            _bets[roundId][msg.sender][input.option] += input.amount;
            optionBetTotals[roundId][input.option] += input.amount;
            totalAmount += input.amount;
            emit BetSelectionPlaced(msg.sender, roundId, input.option, input.amount);
        }

        uint256 oldBalance = wagerToken.balanceOf(address(this));
        wagerToken.safeTransferFrom(msg.sender, address(this), totalAmount);
        uint256 newBalance = wagerToken.balanceOf(address(this));
        if (newBalance - oldBalance != totalAmount) revert UnsupportedFeeOnTransferToken();

        round.totalBets += totalAmount;
        if (totalBetByPlayer[roundId][msg.sender] == 0) {
            _playerRounds[msg.sender].push(roundId);
            _roundPlayers[roundId].push(msg.sender);
        }
        totalBetByPlayer[roundId][msg.sender] += totalAmount;

        uint256 oldReserve = round.requiredReserve;
        uint256 newReserve = _calculateRequiredReserve(roundId);
        if (round.totalBets > newReserve) newReserve = round.totalBets;
        uint256 projectedActiveReserve = totalActiveReserve - oldReserve + newReserve;
        uint256 requiredBalance = lockedPlayerPayouts + projectedActiveReserve + safetyBuffer;
        if (newBalance < requiredBalance) revert InsufficientBankroll(requiredBalance, newBalance);

        round.requiredReserve = newReserve;
        totalActiveReserve = projectedActiveReserve;
        emit BetsPlaced(msg.sender, roundId, totalAmount, newReserve);
    }

    /// @notice Closes betting after the deadline and requests result randomness.
    /// @dev Permissionless so a keeper outage cannot permanently stall a round.
    function closeRound(uint256 roundId) external returns (uint256 requestId) {
        Round storage round = _rounds[roundId];
        if (round.state != RoundState.BETTING) revert InvalidState(RoundState.BETTING, round.state);
        if (block.timestamp < round.bettingDeadline) revert BettingStillOpen();
        if (block.timestamp >= uint256(round.bettingDeadline) + vrfTimeout) revert RequestWindowExpired();
        if (round.totalBets == 0) revert EmptyRound();

        round.state = RoundState.WAITING_RANDOMNESS;
        round.randomnessRequestedAt = uint40(block.timestamp);
        requestId = _requestRandomness(roundId);
        emit RoundClosed(roundId, requestId);
    }

    /// @notice Ends an expired round with no bets without paying for VRF.
    function closeEmptyRound(uint256 roundId) external {
        Round storage round = _rounds[roundId];
        if (round.state != RoundState.BETTING) revert InvalidState(RoundState.BETTING, round.state);
        if (block.timestamp < round.bettingDeadline) revert BettingStillOpen();
        if (round.totalBets != 0) revert RoundHasBets();

        round.state = RoundState.SKIPPED;
        if (activeRoundId == roundId) activeRoundId = 0;
        emit RoundSkipped(roundId);
    }

    /// @notice Performs both deterministic shuffles from the single VRF word and settles the round.
    /// @dev Permissionless and retryable. Complex work is intentionally outside the VRF callback.
    function finalizeRound(uint256 roundId) external {
        Round storage round = _rounds[roundId];
        if (round.state != RoundState.RANDOM_READY) {
            revert InvalidState(RoundState.RANDOM_READY, round.state);
        }

        (uint8[3] memory successfulMaleIds, uint8 resultPosition, uint8 winningMaleId) =
            _deriveResult(roundId, round.randomWord);
        uint256 payout = _payoutForOutcome(roundId, resultPosition);

        round.state = RoundState.SETTLED;
        round.successfulMaleIds = successfulMaleIds;
        round.resultPosition = resultPosition;
        round.winningMaleId = winningMaleId;
        round.totalPayout = payout;

        totalActiveReserve -= round.requiredReserve;
        round.requiredReserve = 0;
        lockedPlayerPayouts += payout;
        if (activeRoundId == roundId) activeRoundId = 0;

        emit RoundSettled(roundId, resultPosition, winningMaleId, successfulMaleIds, payout);
    }

    /// @notice Claims the caller's winnings for a settled round.
    function claim(uint256 roundId) external nonReentrant returns (uint256 amount) {
        Round storage round = _rounds[roundId];
        if (round.state != RoundState.SETTLED) revert InvalidState(RoundState.SETTLED, round.state);
        if (claimed[roundId][msg.sender]) revert AlreadyClaimed();

        amount = _claimable(roundId, msg.sender, round.resultPosition);
        if (amount == 0) revert NothingToClaim();

        claimed[roundId][msg.sender] = true;
        lockedPlayerPayouts -= amount;
        wagerToken.safeTransfer(msg.sender, amount);
        emit Claimed(msg.sender, roundId, amount);
    }

    /// @notice Claims winnings from multiple settled rounds and transfers the aggregate once.
    /// @dev Invalid, losing, duplicate and previously claimed rounds are skipped.
    function claimMany(uint256[] calldata roundIds) external nonReentrant returns (uint256 totalAmount) {
        if (roundIds.length == 0 || roundIds.length > MAX_CLAIMS_PER_TRANSACTION) revert TooManyClaims();

        for (uint256 i; i < roundIds.length; ++i) {
            uint256 roundId = roundIds[i];
            Round storage round = _rounds[roundId];
            if (round.state != RoundState.SETTLED || claimed[roundId][msg.sender]) continue;

            uint256 amount = _claimable(roundId, msg.sender, round.resultPosition);
            if (amount == 0) continue;
            claimed[roundId][msg.sender] = true;
            totalAmount += amount;
            emit Claimed(msg.sender, roundId, amount);
        }

        if (totalAmount == 0) revert NothingToClaim();
        lockedPlayerPayouts -= totalAmount;
        wagerToken.safeTransfer(msg.sender, totalAmount);
    }

    /// @notice Cancels a funded round that never successfully requested VRF.
    /// @dev A successful closeRound and this cancellation are mutually exclusive.
    function cancelUnrequestedRound(uint256 roundId) external {
        Round storage round = _rounds[roundId];
        if (round.state != RoundState.BETTING) revert InvalidState(RoundState.BETTING, round.state);
        if (round.totalBets == 0) revert EmptyRound();
        if (block.timestamp < uint256(round.bettingDeadline) + vrfTimeout) revert TimeoutNotReached();
        _cancelRound(roundId, round);
    }

    /// @notice Frees the active slot while an old VRF request continues waiting.
    /// @dev The original request and its full payout reserve remain live.
    function releaseStalledRound(uint256 roundId) external {
        Round storage round = _rounds[roundId];
        if (round.state != RoundState.WAITING_RANDOMNESS) {
            revert InvalidState(RoundState.WAITING_RANDOMNESS, round.state);
        }
        if (block.timestamp < uint256(round.randomnessRequestedAt) + vrfTimeout) revert TimeoutNotReached();
        if (activeRoundId == roundId) {
            activeRoundId = 0;
            emit StalledRoundReleased(roundId);
        }
    }

    /// @notice Refunds a request that is still unanswered at the fixed final deadline.
    /// @dev The deadline, rather than the caller or transaction ordering after it, decides validity.
    function cancelTimedOutRound(uint256 roundId) external {
        Round storage round = _rounds[roundId];
        if (round.state != RoundState.WAITING_RANDOMNESS) revert RandomnessAlreadyAvailable();
        if (block.timestamp < uint256(round.randomnessRequestedAt) + VRF_FINAL_TIMEOUT) revert TimeoutNotReached();
        _cancelRound(roundId, round);
    }

    /// @notice Returns principal to the next contiguous batch of players after a whole-round cancellation.
    /// @dev Anyone may advance the cursor, but no caller can select recipients or refund amounts.
    function refundBatch(uint256 roundId, uint256 maxPlayers) external nonReentrant returns (uint256 count) {
        Round storage round = _rounds[roundId];
        if (round.state != RoundState.CANCELLED) revert InvalidState(RoundState.CANCELLED, round.state);
        if (maxPlayers == 0 || maxPlayers > MAX_REFUNDS_PER_TRANSACTION) revert InvalidRefundBatchSize();
        uint256 cursor = refundCursor[roundId];
        uint256 length = _roundPlayers[roundId].length;
        if (cursor == length) revert NothingToClaim();
        uint256 end = cursor + maxPlayers;
        if (end > length) end = length;

        refundCursor[roundId] = end;
        for (uint256 i = cursor; i < end; ++i) {
            address player = _roundPlayers[roundId][i];
            uint256 amount = totalBetByPlayer[roundId][player];
            if (wagerToken.trySafeTransfer(player, amount)) {
                refunded[roundId][player] = true;
                lockedPlayerPayouts -= amount;
                emit Refunded(player, roundId, amount);
            } else {
                refundDeferred[roundId][player] = true;
                emit RefundDeferred(player, roundId, amount);
            }
        }
        count = end - cursor;
    }

    /// @notice Allows only a failed recipient to retry receiving their unchanged principal.
    function claimDeferredRefund(uint256 roundId) external nonReentrant returns (uint256 amount) {
        if (!refundDeferred[roundId][msg.sender]) revert RefundNotDeferred();
        amount = totalBetByPlayer[roundId][msg.sender];
        refundDeferred[roundId][msg.sender] = false;
        refunded[roundId][msg.sender] = true;
        lockedPlayerPayouts -= amount;
        wagerToken.safeTransfer(msg.sender, amount);
        emit Refunded(msg.sender, roundId, amount);
    }

    function roundPlayerCount(uint256 roundId) external view returns (uint256) {
        return _roundPlayers[roundId].length;
    }

    /// @notice Adds tokens to the shared bankroll.
    function fundBankroll(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        uint256 oldBalance = wagerToken.balanceOf(address(this));
        wagerToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = wagerToken.balanceOf(address(this)) - oldBalance;
        if (received != amount) revert UnsupportedFeeOnTransferToken();
        emit BankrollFunded(msg.sender, amount);
    }

    /// @notice Withdraws only funds not reserved for active rounds or player claims.
    function withdrawFreeFunds(address recipient, uint256 amount) external onlyOwner nonReentrant {
        if (recipient == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        uint256 available = withdrawableFunds();
        if (amount > available) revert InsufficientBankroll(amount, available);
        wagerToken.safeTransfer(recipient, amount);
        emit FreeFundsWithdrawn(recipient, amount);
    }

    function setKeeper(address keeper, bool allowed) external onlyOwner {
        if (keeper == address(0)) revert InvalidAddress();
        _keeperEpoch[keeper] = allowed ? keeperEpoch : 0;
        emit KeeperUpdated(keeper, allowed);
    }

    function keepers(address keeper) public view returns (bool) {
        return keeper != address(0) && _keeperEpoch[keeper] == keeperEpoch;
    }

    /// @dev All keeper grants from the previous owner expire only when the new owner accepts.
    function acceptOwnership() public override {
        super.acceptOwnership();
        ++keeperEpoch;
    }

    function setSafetyBuffer(uint256 newBuffer) external onlyOwner {
        uint256 oldBuffer = safetyBuffer;
        safetyBuffer = newBuffer;
        emit SafetyBufferUpdated(oldBuffer, newBuffer);
    }

    /// @notice Pauses only new rounds and new bets. Close, settle, claim and refund remain available.
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function getRound(uint256 roundId) external view returns (Round memory) {
        return _rounds[roundId];
    }

    function getRoundLifecycle(uint256 roundId)
        external
        view
        returns (RoundState state, uint40 bettingDeadline, uint40 randomnessRequestedAt, uint256 totalBets)
    {
        Round storage round = _rounds[roundId];
        return (round.state, round.bettingDeadline, round.randomnessRequestedAt, round.totalBets);
    }

    /// @notice Reproduces the two shuffles for public verification of a revealed VRF word.
    function previewResult(uint256 roundId, uint256 vrfSeed)
        external
        pure
        returns (uint8[3] memory successfulMaleIds, uint8 resultPosition, uint8 winningMaleId)
    {
        return _deriveResult(roundId, vrfSeed);
    }

    function getBet(uint256 roundId, address player, BetOption option) external view returns (uint256) {
        return _bets[roundId][player][option];
    }

    function getPlayerBets(uint256 roundId, address player) external view returns (uint256[12] memory amounts) {
        for (uint8 optionIndex; optionIndex < BET_OPTION_COUNT; ++optionIndex) {
            amounts[optionIndex] = _bets[roundId][player][BetOption(optionIndex)];
        }
    }

    function getRoundOptionTotals(uint256 roundId) external view returns (uint256[12] memory amounts) {
        for (uint8 optionIndex; optionIndex < BET_OPTION_COUNT; ++optionIndex) {
            amounts[optionIndex] = optionBetTotals[roundId][BetOption(optionIndex)];
        }
    }

    function playerRoundCount(address player) external view returns (uint256) {
        return _playerRounds[player].length;
    }

    /// @notice Returns an ascending slice of rounds recorded directly when the player first bet.
    function getPlayerRounds(address player, uint256 offset, uint256 limit)
        external
        view
        returns (uint256[] memory roundIds)
    {
        uint256 count = _playerRounds[player].length;
        if (offset >= count || limit == 0) return new uint256[](0);
        if (limit > MAX_PLAYER_ROUNDS_PAGE) limit = MAX_PLAYER_ROUNDS_PAGE;
        uint256 end = offset + limit;
        if (end > count) end = count;
        roundIds = new uint256[](end - offset);
        for (uint256 i; i < roundIds.length; ++i) roundIds[i] = _playerRounds[player][offset + i];
    }

    function claimable(uint256 roundId, address player) external view returns (uint256) {
        Round storage round = _rounds[roundId];
        if (round.state != RoundState.SETTLED || claimed[roundId][player]) return 0;
        return _claimable(roundId, player, round.resultPosition);
    }

    function claimableBatch(address player, uint256[] calldata roundIds)
        external
        view
        returns (uint256[] memory amounts, uint256 totalAmount)
    {
        if (roundIds.length > MAX_PLAYER_ROUNDS_PAGE) revert TooManyClaims();
        amounts = new uint256[](roundIds.length);
        for (uint256 i; i < roundIds.length; ++i) {
            uint256 roundId = roundIds[i];
            Round storage round = _rounds[roundId];
            if (round.state != RoundState.SETTLED || claimed[roundId][player]) continue;
            uint256 amount = _claimable(roundId, player, round.resultPosition);
            amounts[i] = amount;
            totalAmount += amount;
        }
    }

    function withdrawableFunds() public view returns (uint256) {
        uint256 balance = wagerToken.balanceOf(address(this));
        uint256 unavailable = lockedPlayerPayouts + totalActiveReserve + safetyBuffer;
        return balance > unavailable ? balance - unavailable : 0;
    }

    /// @notice Previews a batch using the current on-chain state. The final transaction rechecks solvency.
    function quoteBets(uint256 roundId, BetInput[] calldata inputs)
        external
        view
        returns (bool accepted, uint256 totalAmount, uint256 newReserve, uint256 projectedBalance)
    {
        Round storage round = _rounds[roundId];
        if (paused() || round.state != RoundState.BETTING || block.timestamp >= round.bettingDeadline) {
            return (false, 0, round.requiredReserve, wagerToken.balanceOf(address(this)));
        }
        if (inputs.length == 0 || inputs.length > MAX_BETS_PER_TRANSACTION) {
            return (false, 0, round.requiredReserve, wagerToken.balanceOf(address(this)));
        }

        uint256[12] memory optionAdds;
        for (uint256 i; i < inputs.length; ++i) {
            BetInput calldata input = inputs[i];
            if (input.amount < minimumBet) {
                return (false, 0, round.requiredReserve, wagerToken.balanceOf(address(this)));
            }
            if (input.option == BetOption.DAY) {
                if (input.amount % 10 != 0) {
                    return (false, 0, round.requiredReserve, wagerToken.balanceOf(address(this)));
                }
            }
            optionAdds[uint8(input.option)] += input.amount;
            totalAmount += input.amount;
        }

        newReserve = _calculateRequiredReserveWithAdds(roundId, optionAdds);
        uint256 projectedRoundBets = round.totalBets + totalAmount;
        if (projectedRoundBets > newReserve) newReserve = projectedRoundBets;
        projectedBalance = wagerToken.balanceOf(address(this)) + totalAmount;
        uint256 projectedActiveReserve = totalActiveReserve - round.requiredReserve + newReserve;
        accepted = projectedBalance >= lockedPlayerPayouts + projectedActiveReserve + safetyBuffer;
    }

    /// @dev The callback only stores the VRF word. Both shuffles run in finalizeRound.
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        RequestInfo storage request = vrfRequests[requestId];
        uint256 roundId = request.roundId;
        if (roundId == 0 || request.fulfilled || randomWords.length == 0) {
            emit RandomnessFulfillmentIgnored(requestId, roundId);
            return;
        }

        request.fulfilled = true;
        Round storage round = _rounds[roundId];
        if (
            round.state == RoundState.WAITING_RANDOMNESS
                && block.timestamp < uint256(round.randomnessRequestedAt) + VRF_FINAL_TIMEOUT
        ) {
            round.randomWord = randomWords[0];
            round.state = RoundState.RANDOM_READY;
            emit ResultRandomnessReady(roundId, requestId, randomWords[0]);
            return;
        }

        emit RandomnessFulfillmentIgnored(requestId, roundId);
    }

    function _cancelRound(uint256 roundId, Round storage round) private {
        round.state = RoundState.CANCELLED;
        totalActiveReserve -= round.requiredReserve;
        round.requiredReserve = 0;
        lockedPlayerPayouts += round.totalBets;
        if (activeRoundId == roundId) activeRoundId = 0;
        emit RoundCancelled(roundId, round.totalBets);
    }

    function _requestRandomness(uint256 roundId) private returns (uint256 requestId) {
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: vrfKeyHash,
                subId: vrfSubscriptionId,
                requestConfirmations: vrfRequestConfirmations,
                callbackGasLimit: vrfCallbackGasLimit,
                numWords: NUM_RANDOM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: payVrfWithNative})
                )
            })
        );
        vrfRequests[requestId] = RequestInfo({roundId: roundId, fulfilled: false});
    }

    function _calculateRequiredReserve(uint256 roundId) private view returns (uint256 maximum) {
        for (uint8 optionIndex; optionIndex < uint8(BetOption.DAY); ++optionIndex) {
            BetOption rangeOption = BetOption(optionIndex);
            uint256 rangePayout = optionBetTotals[roundId][rangeOption] * _rangeReturnMultiplier(rangeOption);
            if (rangePayout > maximum) maximum = rangePayout;
        }
        uint256 dayPayout = (optionBetTotals[roundId][BetOption.DAY] * 19) / 10;
        uint256 nightPayout = optionBetTotals[roundId][BetOption.NIGHT] * 2;
        maximum += dayPayout > nightPayout ? dayPayout : nightPayout;
    }

    function _calculateRequiredReserveWithAdds(uint256 roundId, uint256[12] memory optionAdds)
        private
        view
        returns (uint256 maximum)
    {
        for (uint8 optionIndex; optionIndex < uint8(BetOption.DAY); ++optionIndex) {
            BetOption rangeOption = BetOption(optionIndex);
            uint256 rangeTotal = optionBetTotals[roundId][rangeOption] + optionAdds[optionIndex];
            uint256 rangePayout = rangeTotal * _rangeReturnMultiplier(rangeOption);
            if (rangePayout > maximum) maximum = rangePayout;
        }
        uint256 dayTotal = optionBetTotals[roundId][BetOption.DAY] + optionAdds[uint8(BetOption.DAY)];
        uint256 nightTotal = optionBetTotals[roundId][BetOption.NIGHT] + optionAdds[uint8(BetOption.NIGHT)];
        uint256 dayPayout = (dayTotal * 19) / 10;
        uint256 nightPayout = nightTotal * 2;
        maximum += dayPayout > nightPayout ? dayPayout : nightPayout;
    }

    function _payoutForOutcome(uint256 roundId, uint8 position) private view returns (uint256) {
        BetOption rangeOption = _rangeOptionForPosition(position);
        uint256 payout = optionBetTotals[roundId][rangeOption] * _totalReturnMultiplier(position);
        payout += position % 2 == 1
            ? (optionBetTotals[roundId][BetOption.DAY] * 19) / 10
            : optionBetTotals[roundId][BetOption.NIGHT] * 2;
        return payout;
    }

    function _claimable(uint256 roundId, address player, uint8 position) private view returns (uint256) {
        BetOption rangeOption = _rangeOptionForPosition(position);
        uint256 amount = _bets[roundId][player][rangeOption] * _totalReturnMultiplier(position);
        amount += position % 2 == 1
            ? (_bets[roundId][player][BetOption.DAY] * 19) / 10
            : _bets[roundId][player][BetOption.NIGHT] * 2;
        return amount;
    }

    /// @dev First shuffle selects three successful males. The second shuffle determines
    ///      which selected male appears first and therefore the chase duration (1-49).
    function _deriveResult(uint256 roundId, uint256 vrfSeed)
        private
        pure
        returns (uint8[3] memory successfulMaleIds, uint8 resultPosition, uint8 winningMaleId)
    {
        uint256 selectionSeed = uint256(keccak256(abi.encode(vrfSeed, roundId, "MALE_SELECTION")));
        uint8[51] memory selectionOrder = _orderedMales();
        _shuffle(selectionOrder, selectionSeed);
        successfulMaleIds = [selectionOrder[0], selectionOrder[1], selectionOrder[2]];

        uint256 chaseSeed = uint256(keccak256(abi.encode(vrfSeed, roundId, "CHASE_ORDER")));
        uint8[51] memory chaseOrder = _orderedMales();
        _shuffle(chaseOrder, chaseSeed);

        for (uint8 i; i < MALE_COUNT; ++i) {
            uint8 maleId = chaseOrder[i];
            if (
                maleId == successfulMaleIds[0] || maleId == successfulMaleIds[1]
                    || maleId == successfulMaleIds[2]
            ) {
                return (successfulMaleIds, i + 1, maleId);
            }
        }
        assert(false);
        return (successfulMaleIds, 0, 0);
    }

    function _orderedMales() private pure returns (uint8[51] memory males) {
        for (uint8 i; i < MALE_COUNT; ++i) males[i] = i + 1;
    }

    function _shuffle(uint8[51] memory values, uint256 seed) private pure {
        for (uint256 i = MALE_COUNT - 1; i > 0; --i) {
            uint256 entropy = uint256(keccak256(abi.encode(seed, i)));
            uint256 j = _uniform(entropy, i + 1);
            (values[i], values[j]) = (values[j], values[i]);
        }
    }

    function _rangeOptionForPosition(uint8 position) private pure returns (BetOption) {
        if (position <= 5) return BetOption.RANGE_1_5;
        if (position <= 10) return BetOption.RANGE_6_10;
        if (position <= 15) return BetOption.RANGE_11_15;
        if (position <= 20) return BetOption.RANGE_16_20;
        if (position <= 25) return BetOption.RANGE_21_25;
        if (position <= 30) return BetOption.RANGE_26_30;
        if (position <= 35) return BetOption.RANGE_31_35;
        if (position <= 40) return BetOption.RANGE_36_40;
        if (position <= 45) return BetOption.RANGE_41_45;
        return BetOption.RANGE_46_49;
    }

    function _totalReturnMultiplier(uint8 position) private pure returns (uint256) {
        return _rangeReturnMultiplier(_rangeOptionForPosition(position));
    }

    function _rangeReturnMultiplier(BetOption rangeOption) private pure returns (uint256) {
        if (rangeOption == BetOption.RANGE_1_5) return 3;
        if (rangeOption == BetOption.RANGE_6_10) return 4;
        if (rangeOption == BetOption.RANGE_11_15) return 5;
        if (rangeOption == BetOption.RANGE_16_20) return 6;
        if (rangeOption == BetOption.RANGE_21_25) return 9;
        if (rangeOption == BetOption.RANGE_26_30) return 13;
        if (rangeOption == BetOption.RANGE_31_35) return 21;
        if (rangeOption == BetOption.RANGE_36_40) return 41;
        if (rangeOption == BetOption.RANGE_41_45) return 111;
        return 801;
    }

    /// @dev Rejection sampling avoids modulo bias.
    function _uniform(uint256 entropy, uint256 upperBound) private pure returns (uint256) {
        uint256 minimum = type(uint256).max - (type(uint256).max % upperBound);
        while (entropy >= minimum) entropy = uint256(keccak256(abi.encode(entropy)));
        return entropy % upperBound;
    }
}
