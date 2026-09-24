import assert from "node:assert/strict";
import { ethers } from "hardhat";

const abi = ethers.AbiCoder.defaultAbiCoder();
const UINT256_MAX = (1n << 256n) - 1n;

function hash(types: string[], values: unknown[]) {
  return BigInt(ethers.keccak256(abi.encode(types, values)));
}

function uniform(initialEntropy: bigint, upperBound: bigint) {
  let entropy = initialEntropy;
  const minimum = UINT256_MAX - (UINT256_MAX % upperBound);
  while (entropy >= minimum) entropy = hash(["uint256"], [entropy]);
  return entropy % upperBound;
}

function shuffled(seed: bigint) {
  const values = Array.from({ length: 51 }, (_, index) => index + 1);
  for (let i = 50; i > 0; i -= 1) {
    const entropy = hash(["uint256", "uint256"], [seed, i]);
    const j = Number(uniform(entropy, BigInt(i + 1)));
    [values[i], values[j]] = [values[j], values[i]];
  }
  return values;
}

async function deployGame() {
  const [owner, keeper] = await ethers.getSigners();
  const coordinatorFactory = await ethers.getContractFactory(
    "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol:VRFCoordinatorV2_5Mock",
  );
  const coordinator = await coordinatorFactory.deploy(
    ethers.parseEther("0.25"),
    ethers.parseUnits("1", "gwei"),
    ethers.parseEther("1"),
  );
  await coordinator.waitForDeployment();

  const createReceipt = await (await coordinator.createSubscription()).wait();
  const createdEvent = createReceipt?.logs
    .map((log) => {
      try { return coordinator.interface.parseLog(log); } catch { return null; }
    })
    .find((event) => event?.name === "SubscriptionCreated");
  assert(createdEvent);
  const subscriptionId = createdEvent.args.subId as bigint;
  await (await coordinator.fundSubscription(subscriptionId, ethers.parseEther("100"))).wait();

  const tokenFactory = await ethers.getContractFactory("LKRToken");
  const token = await tokenFactory.deploy(owner.address, ethers.parseEther("1000000"));
  await token.waitForDeployment();

  const gameFactory = await ethers.getContractFactory("LadykillerGame");
  const game = await gameFactory.deploy(
    await token.getAddress(),
    await coordinator.getAddress(),
    ethers.ZeroHash,
    subscriptionId,
    500_000,
    3,
    3_600,
    false,
    0,
    keeper.address,
  );
  await game.waitForDeployment();
  await (await coordinator.addConsumer(subscriptionId, await game.getAddress())).wait();
  return { game, coordinator, token };
}

describe("LadykillerGame rules v3", function () {
  it("keeps the deployment owner separate from the Keeper and expires grants on ownership acceptance", async function () {
    const { game, token, coordinator } = await deployGame();
    const [oldOwner, oldKeeper, newOwner, newKeeper] = await ethers.getSigners();
    assert.equal(await game.owner(), oldOwner.address);
    assert.equal(await game.keepers(oldOwner.address), false);
    assert.equal(await game.keepers(oldKeeper.address), true);

    const factory = await ethers.getContractFactory("LadykillerGame");
    await assert.rejects(factory.deploy(await token.getAddress(), await coordinator.getAddress(),
      ethers.ZeroHash, await game.vrfSubscriptionId(), 500_000, 3, 3_600, false, 0, oldOwner.address));

    await (await game.transferOwnership(newOwner.address)).wait();
    assert.equal(await game.keepers(oldKeeper.address), true);
    await (await game.connect(newOwner).acceptOwnership()).wait();
    assert.equal(await game.keepers(oldKeeper.address), false);
    await assert.rejects(game.connect(oldKeeper).startRound());
    await assert.rejects(game.connect(oldOwner).startRound());
    await (await game.connect(newOwner).setKeeper(newKeeper.address, true)).wait();
    await (await game.connect(newKeeper).startRound()).wait();
    assert.equal(await game.activeRoundId(), 1n);

    // An old grant must not revive even if ownership later returns to the old owner.
    await (await game.connect(newOwner).transferOwnership(oldOwner.address)).wait();
    await (await game.acceptOwnership()).wait();
    assert.equal(await game.keepers(oldKeeper.address), false);
    assert.equal(await game.keepers(newKeeper.address), false);
  });

  it("requires at least one whole wager token for every bet selection and quote", async function () {
    const { game, token } = await deployGame();
    const gameAddress = await game.getAddress();
    assert.equal(await game.minimumBet(), ethers.parseEther("1"));
    await (await token.approve(gameAddress, ethers.MaxUint256)).wait();
    await (await game.fundBankroll(ethers.parseEther("1000"))).wait();
    await (await game.startRound()).wait();
    await assert.rejects(game.placeBets(1n, [[0, ethers.parseEther("0.999999")]]));
    assert.equal((await game.quoteBets(1n, [[0, ethers.parseEther("0.999999")]]))[0], false);
    await (await game.placeBets(1n, [[0, ethers.parseEther("1")]])).wait();
    await (await game.pause()).wait();
    assert.equal((await game.quoteBets(1n, [[0, ethers.parseEther("1")]]))[0], false);
  });

  it("skips a failed refund without marking it paid, then lets only that wallet retry", async function () {
    const { game: originalGame, coordinator } = await deployGame();
    const [owner, keeper, blocked, healthy] = await ethers.getSigners();
    const token = await (await ethers.getContractFactory("SelectiveRefundToken")).deploy(6);
    const game = await (await ethers.getContractFactory("LadykillerGame")).deploy(
      await token.getAddress(), await coordinator.getAddress(), ethers.ZeroHash,
      await originalGame.vrfSubscriptionId(), 500_000, 3, 3_600, false, 0, keeper.address,
    );
    const gameAddress = await game.getAddress();
    assert.equal(await game.minimumBet(), 1_000_000n);
    await (await token.approve(gameAddress, ethers.MaxUint256)).wait();
    await (await token.transfer(blocked.address, 10_000_000n)).wait();
    await (await token.transfer(healthy.address, 10_000_000n)).wait();
    await (await token.connect(blocked).approve(gameAddress, ethers.MaxUint256)).wait();
    await (await token.connect(healthy).approve(gameAddress, ethers.MaxUint256)).wait();
    await (await game.fundBankroll(1_000_000_000n)).wait();
    await (await game.startRound()).wait();
    await assert.rejects(game.connect(blocked).placeBets(1n, [[0, 999_999n]]));
    await (await game.connect(blocked).placeBets(1n, [[0, 1_000_000n]])).wait();
    await (await game.connect(healthy).placeBets(1n, [[1, 1_000_000n]])).wait();
    await (await token.setBlockedRecipient(blocked.address)).wait();
    const deadline = (await game.getRound(1n)).bettingDeadline;
    await ethers.provider.send("evm_setNextBlockTimestamp", [Number(deadline + 3_600n)]);
    await (await game.cancelUnrequestedRound(1n)).wait();

    const healthyBefore = await token.balanceOf(healthy.address);
    await (await game.refundBatch(1n, 50n)).wait();
    assert.equal(await game.refundCursor(1n), 2n);
    assert.equal(await game.refunded(1n, blocked.address), false);
    assert.equal(await game.refundDeferred(1n, blocked.address), true);
    assert.equal(await game.refunded(1n, healthy.address), true);
    assert.equal(await token.balanceOf(healthy.address), healthyBefore + 1_000_000n);
    assert.equal(await game.lockedPlayerPayouts(), 1_000_000n);
    await assert.rejects(game.connect(healthy).claimDeferredRefund(1n));
    await assert.rejects(game.connect(blocked).claimDeferredRefund(1n));
    assert.equal(await game.refundDeferred(1n, blocked.address), true);

    await (await token.setBlockedRecipient(ethers.ZeroAddress)).wait();
    const blockedBefore = await token.balanceOf(blocked.address);
    await (await game.connect(blocked).claimDeferredRefund(1n)).wait();
    assert.equal(await token.balanceOf(blocked.address), blockedBefore + 1_000_000n);
    assert.equal(await game.refundDeferred(1n, blocked.address), false);
    assert.equal(await game.refunded(1n, blocked.address), true);
    assert.equal(await game.lockedPlayerPayouts(), 0n);
    await assert.rejects(game.connect(blocked).claimDeferredRefund(1n));
  });

  it("does not let the owner replace or impersonate the VRF coordinator", async function () {
    const { game, coordinator } = await deployGame();
    const [owner] = await ethers.getSigners();
    const gameAddress = await game.getAddress();
    const coordinatorAddress = await coordinator.getAddress();

    assert.equal(await game.s_vrfCoordinator(), coordinatorAddress);
    assert.equal(game.interface.hasFunction("setCoordinator(address)"), false);
    const migrationCall = new ethers.Interface(["function setCoordinator(address)"])
      .encodeFunctionData("setCoordinator", [owner.address]);
    await assert.rejects(owner.sendTransaction({ to: gameAddress, data: migrationCall }));
    await assert.rejects(game.rawFulfillRandomWords(1n, [123n]));
    assert.equal(await game.s_vrfCoordinator(), coordinatorAddress);
  });

  it("accepts multiple ranges plus day/night with independent amounts", async function () {
    const { game, token } = await deployGame();
    const gameAddress = await game.getAddress();

    await (await token.approve(gameAddress, ethers.MaxUint256)).wait();
    await (await game.fundBankroll(ethers.parseEther("100000"))).wait();
    await (await game.startRound()).wait();

    await (await game.placeBets(1n, [
      [0, ethers.parseEther("1")],
      [4, ethers.parseEther("2")],
      [9, ethers.parseEther("3")],
      [10, ethers.parseEther("4")],
      [11, ethers.parseEther("5")],
    ])).wait();

    assert.equal(await game.getBet(1n, (await ethers.getSigners())[0].address, 0), ethers.parseEther("1"));
    assert.equal(await game.getBet(1n, (await ethers.getSigners())[0].address, 4), ethers.parseEther("2"));
    assert.equal(await game.getBet(1n, (await ethers.getSigners())[0].address, 9), ethers.parseEther("3"));
    assert.equal(await game.getBet(1n, (await ethers.getSigners())[0].address, 10), ethers.parseEther("4"));
    assert.equal(await game.getBet(1n, (await ethers.getSigners())[0].address, 11), ethers.parseEther("5"));
    assert.equal(await game.totalBetByPlayer(1n, (await ethers.getSigners())[0].address), ethers.parseEther("15"));
    assert.equal((await game.getRound(1n)).totalBets, ethers.parseEther("15"));
  });

  it("settles range and parity bets using the displayed total-return multipliers", async function () {
    const { game, coordinator, token } = await deployGame();
    const [player] = await ethers.getSigners();
    const gameAddress = await game.getAddress();
    const rangeAmounts = Array.from({ length: 10 }, (_, index) => ethers.parseEther(String(index + 1)));
    const dayAmount = ethers.parseEther("20");
    const nightAmount = ethers.parseEther("30");
    const inputs = [
      ...rangeAmounts.map((amount, option) => [option, amount]),
      [10, dayAmount],
      [11, nightAmount],
    ];

    await (await token.approve(gameAddress, ethers.MaxUint256)).wait();
    await (await game.fundBankroll(ethers.parseEther("900000"))).wait();
    await (await game.startRound()).wait();
    await (await game.placeBets(1n, inputs)).wait();

    await ethers.provider.send("evm_increaseTime", [46]);
    await ethers.provider.send("evm_mine", []);
    const closeReceipt = await (await game.closeRound(1n)).wait();
    const closeEvent = closeReceipt?.logs
      .map((log) => {
        try { return game.interface.parseLog(log); } catch { return null; }
      })
      .find((event) => event?.name === "RoundClosed");
    assert(closeEvent);

    await (await coordinator.fulfillRandomWordsWithOverride(
      closeEvent.args.requestId as bigint,
      gameAddress,
      [987654321n],
    )).wait();
    await (await game.finalizeRound(1n)).wait();

    const resultPosition = Number((await game.getRound(1n)).resultPosition);
    const rangeOption = resultPosition <= 45 ? Math.floor((resultPosition - 1) / 5) : 9;
    const multipliers = [3n, 4n, 5n, 6n, 9n, 13n, 21n, 41n, 111n, 801n];
    const rangePayout = rangeAmounts[rangeOption] * multipliers[rangeOption];
    const parityPayout = resultPosition % 2 === 1 ? dayAmount * 19n / 10n : nightAmount * 2n;
    const expected = rangePayout + parityPayout;

    assert.equal(await game.claimable(1n, player.address), expected);
    assert.equal((await game.getRound(1n)).totalPayout, expected);
    const balanceBefore = await token.balanceOf(player.address);
    await (await game.claim(1n)).wait();
    assert.equal(await token.balanceOf(player.address), balanceBefore + expected);
  });

  it("records player rounds on-chain and claims multiple winning rounds in one transfer", async function () {
    const { game, coordinator, token } = await deployGame();
    const [player] = await ethers.getSigners();
    const gameAddress = await game.getAddress();
    await (await token.approve(gameAddress, ethers.MaxUint256)).wait();
    await (await game.fundBankroll(ethers.parseEther("900000"))).wait();

    const settle = async (roundId: bigint, seed: bigint) => {
      await (await game.startRound()).wait();
      await (await game.placeBets(roundId, [
        ...Array.from({ length: 10 }, (_, option) => [option, ethers.parseEther("1")]),
        [10, ethers.parseEther("10")],
        [11, ethers.parseEther("10")],
      ])).wait();
      // A second transaction in the same round must not duplicate the participation index.
      await (await game.placeBets(roundId, [[0, ethers.parseEther("1")]])).wait();
      await ethers.provider.send("evm_increaseTime", [46]);
      await ethers.provider.send("evm_mine", []);
      const closeReceipt = await (await game.closeRound(roundId)).wait();
      const closeEvent = closeReceipt?.logs
        .map((log) => {
          try { return game.interface.parseLog(log); } catch { return null; }
        })
        .find((event) => event?.name === "RoundClosed");
      assert(closeEvent);
      await (await coordinator.fulfillRandomWordsWithOverride(
        closeEvent.args.requestId as bigint,
        gameAddress,
        [seed],
      )).wait();
      await (await game.finalizeRound(roundId)).wait();
    };

    await settle(1n, 111n);
    await settle(2n, 222n);

    assert.equal(await game.playerRoundCount(player.address), 2n);
    assert.deepEqual((await game.getPlayerRounds(player.address, 0n, 100n)).map(Number), [1, 2]);
    const [amounts, total] = await game.claimableBatch(player.address, [1n, 2n]);
    assert(amounts[0] > 0n && amounts[1] > 0n);
    assert.equal(total, amounts[0] + amounts[1]);

    const balanceBefore = await token.balanceOf(player.address);
    await (await game.claimMany([1n, 2n, 1n, 999n])).wait();
    assert.equal(await token.balanceOf(player.address), balanceBefore + total);
    assert.equal(await game.claimed(1n, player.address), true);
    assert.equal(await game.claimed(2n, player.address), true);
    const [, remaining] = await game.claimableBatch(player.address, [1n, 2n]);
    assert.equal(remaining, 0n);
    await assert.rejects(game.claimMany([1n, 2n]));
  });

  it("opens betting first and requests exactly one VRF word only after the deadline", async function () {
    const { game, coordinator, token } = await deployGame();

    await (await game.startRound()).wait();
    const opened = await game.getRound(1n);
    assert.equal(opened.state, 1n);
    assert.equal(opened.rulesVersion, 3n);
    assert.equal(opened.bettingDeadline - opened.bettingStart, 45n);
    assert.equal(await game.activeRoundId(), 1n);
    assert.equal((await game.vrfRequests(1n)).roundId, 0n);
    await assert.rejects(game.closeRound(1n));

    await (await token.approve(await game.getAddress(), ethers.MaxUint256)).wait();
    await (await game.fundBankroll(ethers.parseEther("1000"))).wait();
    await (await game.placeBets(1n, [[0, ethers.parseEther("1")]])).wait();

    await ethers.provider.send("evm_increaseTime", [46]);
    await ethers.provider.send("evm_mine", []);
    await assert.rejects(game.closeEmptyRound(1n));
    const closeReceipt = await (await game.closeRound(1n)).wait();
    const closeEvent = closeReceipt?.logs
      .map((log) => {
        try { return game.interface.parseLog(log); } catch { return null; }
      })
      .find((event) => event?.name === "RoundClosed");
    assert(closeEvent);
    const requestId = closeEvent.args.requestId as bigint;
    assert.equal((await game.getRound(1n)).state, 2n);
    assert.equal((await game.vrfRequests(requestId)).roundId, 1n);

    const vrfSeed = 123456789n;
    const fulfillReceipt = await (
      await coordinator.fulfillRandomWordsWithOverride(requestId, await game.getAddress(), [vrfSeed])
    ).wait();
    assert.equal((await game.getRound(1n)).state, 3n);
    const readyEvent = fulfillReceipt?.logs
      .map((log) => {
        try { return game.interface.parseLog(log); } catch { return null; }
      })
      .find((event) => event?.name === "ResultRandomnessReady");
    assert(readyEvent);
    assert.equal(readyEvent.args.randomWord, vrfSeed);

    const selectionSeed = hash(["uint256", "uint256", "string"], [vrfSeed, 1n, "MALE_SELECTION"]);
    const expectedMales = shuffled(selectionSeed).slice(0, 3);
    const chaseSeed = hash(["uint256", "uint256", "string"], [vrfSeed, 1n, "CHASE_ORDER"]);
    const chaseOrder = shuffled(chaseSeed);
    const expectedPosition = chaseOrder.findIndex((maleId) => expectedMales.includes(maleId)) + 1;
    const expectedWinner = chaseOrder[expectedPosition - 1];

    await (await game.finalizeRound(1n)).wait();
    const settled = await game.getRound(1n);
    assert.equal(settled.state, 4n);
    assert.deepEqual(settled.successfulMaleIds.map(Number), expectedMales);
    assert.equal(Number(settled.resultPosition), expectedPosition);
    assert.equal(Number(settled.winningMaleId), expectedWinner);
    assert(expectedPosition >= 1 && expectedPosition <= 49);
    assert.equal(await game.activeRoundId(), 0n);
  });

  it("skips an empty round without VRF and immediately allows the next round", async function () {
    const { game } = await deployGame();
    await (await game.startRound()).wait();
    await assert.rejects(game.startRound());

    await ethers.provider.send("evm_increaseTime", [46]);
    await ethers.provider.send("evm_mine", []);
    await assert.rejects(game.closeRound(1n));
    await (await game.closeEmptyRound(1n)).wait();

    assert.equal((await game.getRound(1n)).state, 6n);
    assert.equal(await game.activeRoundId(), 0n);
    assert.equal((await game.vrfRequests(1n)).roundId, 0n);

    await (await game.startRound()).wait();
    assert.equal(await game.activeRoundId(), 2n);
  });

  it("refunds an expired round when VRF was never requested", async function () {
    const { game, coordinator, token } = await deployGame();
    const [player] = await ethers.getSigners();
    await (await game.startRound()).wait();
    await (await token.approve(await game.getAddress(), ethers.MaxUint256)).wait();
    await (await game.fundBankroll(ethers.parseEther("1000"))).wait();
    await (await game.placeBets(1n, [[0, ethers.parseEther("1")]])).wait();
    const deadline = (await game.getRound(1n)).bettingDeadline;

    await (await coordinator.removeConsumer(await game.vrfSubscriptionId(), await game.getAddress())).wait();
    await ethers.provider.send("evm_setNextBlockTimestamp", [Number(deadline)]);
    await assert.rejects(game.closeRound(1n));
    assert.equal((await game.getRound(1n)).state, 1n);
    await assert.rejects(game.cancelUnrequestedRound(1n));

    const expiry = deadline + await game.vrfTimeout();
    await ethers.provider.send("evm_setNextBlockTimestamp", [Number(expiry)]);
    await assert.rejects(game.closeRound(1n));
    await (await game.cancelUnrequestedRound(1n)).wait();
    assert.equal((await game.getRound(1n)).state, 5n);
    assert.equal(await game.activeRoundId(), 0n);
    assert.equal(await game.lockedPlayerPayouts(), ethers.parseEther("1"));
    assert.equal(await game.totalActiveReserve(), 0n);
    await assert.rejects(game.closeRound(1n));
    await (await game.refundBatch(1n, 50n)).wait();
    assert.equal(await game.refunded(1n, player.address), true);
    assert.equal(await game.lockedPlayerPayouts(), 0n);
  });

  it("releases a stalled request without discarding its later valid result", async function () {
    const { game, coordinator, token } = await deployGame();
    await (await game.startRound()).wait();
    await (await token.approve(await game.getAddress(), ethers.MaxUint256)).wait();
    await (await game.fundBankroll(ethers.parseEther("1000"))).wait();
    await (await game.placeBets(1n, [[0, ethers.parseEther("1")]])).wait();

    await ethers.provider.send("evm_increaseTime", [46]);
    await ethers.provider.send("evm_mine", []);
    const closeReceipt = await (await game.closeRound(1n)).wait();
    const closeEvent = closeReceipt?.logs
      .map((log) => { try { return game.interface.parseLog(log); } catch { return null; } })
      .find((event) => event?.name === "RoundClosed");
    assert(closeEvent);
    const requestId = closeEvent.args.requestId as bigint;
    const requestedAt = (await game.getRound(1n)).randomnessRequestedAt;
    await assert.rejects(game.releaseStalledRound(1n));
    await ethers.provider.send("evm_setNextBlockTimestamp", [Number(requestedAt + await game.vrfTimeout())]);
    await (await game.releaseStalledRound(1n)).wait();
    assert.equal((await game.getRound(1n)).state, 2n);
    assert(await game.totalActiveReserve() > 0n);
    assert.equal(await game.activeRoundId(), 0n);
    await (await game.startRound()).wait();
    assert.equal(await game.activeRoundId(), 2n);
    await (await coordinator.fulfillRandomWordsWithOverride(requestId, await game.getAddress(), [123n])).wait();
    await (await game.finalizeRound(1n)).wait();
    assert.equal((await game.getRound(1n)).state, 4n);
    assert.equal(await game.activeRoundId(), 2n);
  });

  it("allows VRF to recover before the pre-request deadline", async function () {
    const { game, coordinator, token } = await deployGame();
    await (await game.startRound()).wait();
    await (await token.approve(await game.getAddress(), ethers.MaxUint256)).wait();
    await (await game.fundBankroll(ethers.parseEther("1000"))).wait();
    await (await game.placeBets(1n, [[0, ethers.parseEther("1")]])).wait();
    await (await coordinator.removeConsumer(await game.vrfSubscriptionId(), await game.getAddress())).wait();
    const expiry = (await game.getRound(1n)).bettingDeadline + await game.vrfTimeout();
    await ethers.provider.send("evm_setNextBlockTimestamp", [Number(expiry - 100n)]);
    await ethers.provider.send("evm_mine", []);
    await assert.rejects(game.closeRound(1n));
    await (await coordinator.addConsumer(await game.vrfSubscriptionId(), await game.getAddress())).wait();
    await (await game.closeRound(1n)).wait();
    assert.equal((await game.getRound(1n)).state, 2n);
    await assert.rejects(game.cancelUnrequestedRound(1n));
  });

  it("preserves a timely VRF result even if finalization happens after the refund deadline", async function () {
    const { game, coordinator, token } = await deployGame();
    await (await game.startRound()).wait();
    await (await token.approve(await game.getAddress(), ethers.MaxUint256)).wait();
    await (await game.fundBankroll(ethers.parseEther("1000"))).wait();
    await (await game.placeBets(1n, [[0, ethers.parseEther("1")]])).wait();
    await ethers.provider.send("evm_increaseTime", [46]);
    await ethers.provider.send("evm_mine", []);
    const receipt = await (await game.closeRound(1n)).wait();
    const event = receipt?.logs.map((log) => {
      try { return game.interface.parseLog(log); } catch { return null; }
    }).find((item) => item?.name === "RoundClosed");
    assert(event);
    const deadline = (await game.getRound(1n)).randomnessRequestedAt + await game.VRF_FINAL_TIMEOUT();
    await ethers.provider.send("evm_setNextBlockTimestamp", [Number(deadline - 1n)]);
    await (await coordinator.fulfillRandomWordsWithOverride(event.args.requestId as bigint,
      await game.getAddress(), [123n])).wait();
    assert.equal((await game.getRound(1n)).state, 3n);
    await ethers.provider.send("evm_setNextBlockTimestamp", [Number(deadline)]);
    await (await game.finalizeRound(1n)).wait();
    assert.equal((await game.getRound(1n)).state, 4n);
    await assert.rejects(game.cancelTimedOutRound(1n));
  });

  it("refunds at the fixed final deadline and ignores late VRF regardless of transaction order", async function () {
    const { game, coordinator, token } = await deployGame();
    const [player] = await ethers.getSigners();
    await (await game.startRound()).wait();
    await (await token.approve(await game.getAddress(), ethers.MaxUint256)).wait();
    await (await game.fundBankroll(ethers.parseEther("1000"))).wait();
    await (await game.placeBets(1n, [[0, ethers.parseEther("1")]])).wait();

    await ethers.provider.send("evm_increaseTime", [46]);
    await ethers.provider.send("evm_mine", []);
    const closeReceipt = await (await game.closeRound(1n)).wait();
    const closeEvent = closeReceipt?.logs
      .map((log) => { try { return game.interface.parseLog(log); } catch { return null; } })
      .find((event) => event?.name === "RoundClosed");
    assert(closeEvent);
    const requestId = closeEvent.args.requestId as bigint;
    const requestedAt = (await game.getRound(1n)).randomnessRequestedAt;
    const finalDeadline = requestedAt + await game.VRF_FINAL_TIMEOUT();
    assert.equal(await game.VRF_FINAL_TIMEOUT(), 86_400n);
    await ethers.provider.send("evm_setNextBlockTimestamp", [Number(finalDeadline - 1n)]);
    await assert.rejects(game.cancelTimedOutRound(1n));
    await ethers.provider.send("evm_setNextBlockTimestamp", [Number(finalDeadline)]);
    await (await coordinator.fulfillRandomWordsWithOverride(requestId, await game.getAddress(), [123n])).wait();
    assert.equal((await game.getRound(1n)).state, 2n);
    await (await game.cancelTimedOutRound(1n)).wait();

    assert.equal((await game.getRound(1n)).state, 5n);
    assert.equal(await game.activeRoundId(), 0n);
    await (await game.refundBatch(1n, 50n)).wait();
    assert.equal(await game.refunded(1n, player.address), true);
    await (await game.startRound()).wait();
    assert.equal(await game.activeRoundId(), 2n);
  });

  it("refunds every bettor in fixed batches, not a caller-selected subset", async function () {
    const { game, token } = await deployGame();
    const [first, second] = await ethers.getSigners();
    const gameAddress = await game.getAddress();
    await (await token.transfer(second.address, ethers.parseEther("10"))).wait();
    await (await token.approve(gameAddress, ethers.MaxUint256)).wait();
    await (await token.connect(second).approve(gameAddress, ethers.MaxUint256)).wait();
    await (await game.fundBankroll(ethers.parseEther("1000"))).wait();
    await (await game.startRound()).wait();
    await (await game.placeBets(1n, [[0, ethers.parseEther("1")]])).wait();
    await (await game.placeBets(1n, [[1, ethers.parseEther("2")]])).wait();
    await (await game.connect(second).placeBets(1n, [[2, ethers.parseEther("3")]])).wait();
    assert.equal(await game.roundPlayerCount(1n), 2n);

    const deadline = (await game.getRound(1n)).bettingDeadline;
    const expiry = deadline + await game.vrfTimeout();
    await ethers.provider.send("evm_setNextBlockTimestamp", [Number(expiry)]);
    await (await game.cancelUnrequestedRound(1n)).wait();
    assert.equal(await game.lockedPlayerPayouts(), ethers.parseEther("6"));
    await assert.rejects(game.refundBatch(1n, 0n));
    await assert.rejects(game.refundBatch(1n, 51n));

    const firstBefore = await token.balanceOf(first.address);
    const secondBefore = await token.balanceOf(second.address);
    await (await game.connect(second).refundBatch(1n, 1n)).wait();
    assert.equal(await token.balanceOf(first.address), firstBefore + ethers.parseEther("3"));
    assert.equal(await token.balanceOf(second.address), secondBefore);
    assert.equal(await game.refundCursor(1n), 1n);
    await (await game.refundBatch(1n, 1n)).wait();
    assert.equal(await token.balanceOf(second.address), secondBefore + ethers.parseEther("3"));
    assert.equal(await game.refundCursor(1n), 2n);
    assert.equal(await game.lockedPlayerPayouts(), 0n);
    await assert.rejects(game.refundBatch(1n, 1n));
  });

  it("always returns three distinct males from 1-51 and a day from 1-49", async function () {
    const { game } = await deployGame();
    for (let seed = 1n; seed <= 25n; seed += 1n) {
      const [maleIds, position, winner] = await game.previewResult(9n, seed);
      const values = maleIds.map(Number);
      assert.equal(new Set(values).size, 3);
      assert(values.every((maleId) => maleId >= 1 && maleId <= 51));
      assert(Number(position) >= 1 && Number(position) <= 49);
      assert(values.includes(Number(winner)));
    }
  });
});
