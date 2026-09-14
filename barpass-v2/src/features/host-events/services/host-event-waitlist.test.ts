import { describe, it, expect } from "vitest";
import {
  claimExpiryFor,
  expireLapsedOffers,
  isOfferClaimable,
  orderQueue,
  planOffers,
  queuePosition,
  type WaitlistEntry,
} from "./host-event-rules";

/**
 * The DICE mechanic: a sold-out tier queues by join time, a released spot is
 * offered down that queue at face value with a time-boxed claim window, and a
 * lapsed window passes the spot to the next person rather than to a reseller.
 */

const at = (iso: string) => new Date(iso);
const queue = (): WaitlistEntry[] => [
  { id: "c", userId: "carol", joinedAt: "2026-09-14T18:00:02.000Z", state: "waiting" },
  { id: "a", userId: "alice", joinedAt: "2026-09-14T18:00:00.000Z", state: "waiting" },
  { id: "b", userId: "bob", joinedAt: "2026-09-14T18:00:01.000Z", state: "waiting" },
];

describe("orderQueue", () => {
  it("orders strictly by join time — no priority, no paying to skip", () => {
    expect(orderQueue(queue()).map((e) => e.userId)).toEqual(["alice", "bob", "carol"]);
  });

  it("breaks an exact tie by id, deterministically", () => {
    const sameInstant: WaitlistEntry[] = [
      { id: "zz", userId: "z", joinedAt: "2026-09-14T18:00:00.000Z", state: "waiting" },
      { id: "aa", userId: "a", joinedAt: "2026-09-14T18:00:00.000Z", state: "waiting" },
    ];
    expect(orderQueue(sameInstant).map((e) => e.id)).toEqual(["aa", "zz"]);
    expect(orderQueue([...sameInstant].reverse()).map((e) => e.id)).toEqual(["aa", "zz"]);
  });

  it("drops entries that are no longer live", () => {
    const mixed: WaitlistEntry[] = [
      ...queue(),
      { id: "d", userId: "dave", joinedAt: "2026-09-14T17:00:00.000Z", state: "claimed" },
      { id: "e", userId: "erin", joinedAt: "2026-09-14T17:30:00.000Z", state: "left" },
    ];
    expect(orderQueue(mixed).map((e) => e.userId)).toEqual(["alice", "bob", "carol"]);
  });

  it("does not mutate the input", () => {
    const input = queue();
    orderQueue(input);
    expect(input.map((e) => e.id)).toEqual(["c", "a", "b"]);
  });
});

describe("claim windows", () => {
  const offeredAt = at("2026-09-14T20:00:00.000Z");

  it("computes the expiry from the offer instant", () => {
    expect(claimExpiryFor(offeredAt, 30).toISOString()).toBe("2026-09-14T20:30:00.000Z");
  });

  it("is claimable inside the window and not at or after the boundary", () => {
    const entry: WaitlistEntry = {
      id: "a",
      userId: "alice",
      joinedAt: "2026-09-14T18:00:00.000Z",
      state: "offered",
      claimExpiresAt: "2026-09-14T20:30:00.000Z",
    };
    expect(isOfferClaimable(entry, at("2026-09-14T20:29:59.000Z"))).toBe(true);
    expect(isOfferClaimable(entry, at("2026-09-14T20:30:00.000Z"))).toBe(false);
    expect(isOfferClaimable(entry, at("2026-09-14T20:30:01.000Z"))).toBe(false);
  });

  it("a waiting entry is never claimable, however long it has waited", () => {
    expect(isOfferClaimable(queue()[0], at("2030-01-01T00:00:00.000Z"))).toBe(false);
  });

  it("an offer with no expiry recorded is not claimable", () => {
    const broken: WaitlistEntry = { ...queue()[0], state: "offered", claimExpiresAt: null };
    expect(isOfferClaimable(broken, offeredAt)).toBe(false);
  });
});

describe("expireLapsedOffers", () => {
  const withOffer = (): WaitlistEntry[] => [
    {
      id: "a",
      userId: "alice",
      joinedAt: "2026-09-14T18:00:00.000Z",
      state: "offered",
      claimExpiresAt: "2026-09-14T20:30:00.000Z",
    },
    { id: "b", userId: "bob", joinedAt: "2026-09-14T18:00:01.000Z", state: "waiting" },
  ];

  it("leaves a live offer alone", () => {
    expect(expireLapsedOffers(withOffer(), at("2026-09-14T20:00:00.000Z"))[0].state).toBe("offered");
  });

  it("expires a lapsed offer — it does NOT go back to waiting", () => {
    const after = expireLapsedOffers(withOffer(), at("2026-09-14T21:00:00.000Z"));
    expect(after[0].state).toBe("expired");
    expect(after.map((e) => e.state)).not.toContain("waiting_again");
    expect(orderQueue(after).map((e) => e.userId)).toEqual(["bob"]);
  });

  it("does not mutate the input", () => {
    const input = withOffer();
    expireLapsedOffers(input, at("2026-09-14T21:00:00.000Z"));
    expect(input[0].state).toBe("offered");
  });
});

describe("queuePosition", () => {
  const now = at("2026-09-14T18:05:00.000Z");

  it("is 1-based and follows join order", () => {
    expect(queuePosition(queue(), "alice", now)).toBe(1);
    expect(queuePosition(queue(), "bob", now)).toBe(2);
    expect(queuePosition(queue(), "carol", now)).toBe(3);
  });

  it("is null for someone who isn't queued", () => {
    expect(queuePosition(queue(), "mallory", now)).toBeNull();
  });

  it("moves everyone up when the person ahead lets their offer lapse", () => {
    const entries: WaitlistEntry[] = [
      {
        id: "a",
        userId: "alice",
        joinedAt: "2026-09-14T18:00:00.000Z",
        state: "offered",
        claimExpiresAt: "2026-09-14T18:30:00.000Z",
      },
      { id: "b", userId: "bob", joinedAt: "2026-09-14T18:00:01.000Z", state: "waiting" },
    ];
    expect(queuePosition(entries, "bob", at("2026-09-14T18:10:00.000Z"))).toBe(2);
    expect(queuePosition(entries, "bob", at("2026-09-14T19:00:00.000Z"))).toBe(1);
  });
});

describe("planOffers — what happens when a holder releases a spot", () => {
  const now = at("2026-09-14T20:00:00.000Z");

  it("offers nothing while the tier is still full", () => {
    const plan = planOffers(queue(), { quantity: 10, claimedCount: 10 }, now, 30);
    expect(plan.offers).toHaveLength(0);
  });

  it("offers one freed seat to the head of the queue, at face value", () => {
    const plan = planOffers(queue(), { quantity: 10, claimedCount: 9 }, now, 30);
    expect(plan.offers.map((e) => e.userId)).toEqual(["alice"]);
    expect(plan.offers[0].claimExpiresAt).toBe("2026-09-14T20:30:00.000Z");
    // Nothing in the plan changes a price: the mechanic exists to kill resale.
    expect(plan.entries.find((e) => e.userId === "bob")?.state).toBe("waiting");
  });

  it("offers exactly as many seats as were freed, in order", () => {
    const plan = planOffers(queue(), { quantity: 10, claimedCount: 8 }, now, 30);
    expect(plan.offers.map((e) => e.userId)).toEqual(["alice", "bob"]);
  });

  it("never offers more seats than exist, even with a long queue", () => {
    const plan = planOffers(queue(), { quantity: 10, claimedCount: 0 }, now, 30);
    expect(plan.offers).toHaveLength(3);
  });

  it("does not re-offer a seat already held by a live offer", () => {
    const entries: WaitlistEntry[] = [
      {
        id: "a",
        userId: "alice",
        joinedAt: "2026-09-14T18:00:00.000Z",
        state: "offered",
        claimExpiresAt: "2026-09-14T20:30:00.000Z",
      },
      { id: "b", userId: "bob", joinedAt: "2026-09-14T18:00:01.000Z", state: "waiting" },
    ];
    const plan = planOffers(entries, { quantity: 10, claimedCount: 9 }, now, 30);
    expect(plan.offers).toHaveLength(0);
  });

  it("passes the offer to the next person once the first window lapses", () => {
    const entries: WaitlistEntry[] = [
      {
        id: "a",
        userId: "alice",
        joinedAt: "2026-09-14T18:00:00.000Z",
        state: "offered",
        claimExpiresAt: "2026-09-14T19:00:00.000Z",
      },
      { id: "b", userId: "bob", joinedAt: "2026-09-14T18:00:01.000Z", state: "waiting" },
      { id: "c", userId: "carol", joinedAt: "2026-09-14T18:00:02.000Z", state: "waiting" },
    ];
    const plan = planOffers(entries, { quantity: 10, claimedCount: 9 }, now, 45);
    expect(plan.offers.map((e) => e.userId)).toEqual(["bob"]);
    expect(plan.entries.find((e) => e.userId === "alice")?.state).toBe("expired");
    expect(plan.offers[0].claimExpiresAt).toBe("2026-09-14T20:45:00.000Z");
  });

  it("is idempotent — re-running it on its own output offers nothing new", () => {
    const first = planOffers(queue(), { quantity: 10, claimedCount: 9 }, now, 30);
    const second = planOffers(first.entries, { quantity: 10, claimedCount: 9 }, now, 30);
    expect(second.offers).toHaveLength(0);
  });
});
