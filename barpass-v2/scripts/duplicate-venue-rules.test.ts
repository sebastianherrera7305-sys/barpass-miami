import { describe, expect, it } from "vitest";
import {
  compareSurvivor,
  groupDuplicates,
  haversineMeters,
  isResolved,
  normalizeAddress,
  normalizeName,
  type VenueRow,
} from "./duplicate-venue-rules";

const row = (over: Partial<VenueRow> & { id: string }): VenueRow => ({
  name: "Bar",
  slug: over.id,
  city: "Gainesville",
  address: "1728 W University Ave, Gainesville, FL 32603, USA",
  lat: 29.6525821,
  lng: -82.3456115,
  review_count: 0,
  rating: null,
  google_place_id: null,
  excluded_reason: null,
  business_status: "OPERATIONAL",
  image_url: null,
  created_at: "2026-01-01T00:00:00Z",
  google_synced_at: null,
  ...over,
});

describe("normalizeAddress", () => {
  it("collapses the spellings Google alternates between", () => {
    expect(normalizeAddress("1728 Southwest 2nd Avenue, Gainesville, FL 32601, USA")).toBe(
      normalizeAddress("1728 SW 2nd Ave., Gainesville, FL 32601"),
    );
  });

  it("keeps different house numbers apart", () => {
    expect(normalizeAddress("1728 W University Ave")).not.toBe(
      normalizeAddress("1730 W University Ave"),
    );
  });

  it("is empty for a missing address, which must never match another empty", () => {
    expect(normalizeAddress(null)).toBe("");
  });
});

describe("normalizeName", () => {
  it("is tolerant of case, punctuation and &", () => {
    expect(normalizeName("MacDinton's GNV")).toBe(normalizeName("macdintons gnv"));
    expect(normalizeName("Bar & Grill")).toBe(normalizeName("Bar and Grill"));
  });
});

describe("haversineMeters", () => {
  it("measures a short hop in metres", () => {
    const d = haversineMeters(
      { lat: 29.6525821, lng: -82.3456115 },
      { lat: 29.6525821, lng: -82.3451115 },
    );
    expect(d).toBeGreaterThan(40);
    expect(d).toBeLessThan(60);
  });
});

describe("groupDuplicates — place_id", () => {
  it("groups two rows sharing a google_place_id", () => {
    const groups = groupDuplicates([
      row({ id: "a", google_place_id: "ChIJ_mac", review_count: 1206 }),
      row({ id: "b", google_place_id: "ChIJ_mac", review_count: 1204, address: "otra" }),
      row({ id: "c", google_place_id: "ChIJ_other" }),
    ]);
    expect(groups).toHaveLength(1);
    expect(groups[0].criterion).toBe("place_id");
    expect(groups[0].rows.map((r) => r.id)).toEqual(["a", "b"]);
  });

  it("never groups rows whose place_id is null", () => {
    expect(groupDuplicates([
      row({ id: "a", address: "x", lat: null, lng: null }),
      row({ id: "b", address: "y", lat: null, lng: null }),
    ])).toHaveLength(0);
  });
});

describe("groupDuplicates — address + geo", () => {
  it("groups same name, same address, same door", () => {
    const groups = groupDuplicates([
      row({ id: "a", name: "MacDinton's GNV" }),
      row({ id: "b", name: "MacDintons GNV", lat: 29.6525901, lng: -82.3456115 }),
    ]);
    expect(groups[0].criterion).toBe("address+geo");
    expect(groups[0].spreadMeters).toBeLessThan(60);
  });

  it("refuses the match when the coordinates are far apart", () => {
    // Same address string, 8km apart: one of the two rows is geocoded wrong,
    // and guessing which would be inventing data.
    expect(groupDuplicates([
      row({ id: "a" }),
      row({ id: "b", lat: 29.72, lng: -82.34 }),
    ])).toHaveLength(0);
  });

  it("refuses the match when either row has no coordinates", () => {
    expect(groupDuplicates([
      row({ id: "a" }),
      row({ id: "b", lat: null, lng: null }),
    ])).toHaveLength(0);
  });

  it("does NOT group three real Sonny's BBQ at three addresses", () => {
    expect(groupDuplicates([
      row({ id: "a", name: "Sonny's BBQ", address: "3635 SW Archer Rd", lat: 29.62, lng: -82.37 }),
      row({ id: "b", name: "Sonny's BBQ", address: "1234 NW 13th St", lat: 29.66, lng: -82.34 }),
      row({ id: "c", name: "Sonny's BBQ", address: "4110 NW 16th Blvd", lat: 29.67, lng: -82.38 }),
    ])).toHaveLength(0);
  });

  it("flags two DIFFERENT names under one roof as same-roof, not a duplicate", () => {
    const groups = groupDuplicates([
      row({ id: "lobby", name: "Lobby Bar" }),
      row({ id: "roof", name: "Rooftop Club" }),
    ]);
    expect(groups[0].criterion).toBe("same-roof");
  });

  it("splits a shared address into the repeated name AND the rest", () => {
    // Real case, Ann Arbor: two Echelon rows plus a genuinely different venue
    // in the same building. Judging the whole bucket as same-roof would hide
    // the duplicate.
    const groups = groupDuplicates([
      row({ id: "e1", name: "Echelon Kitchen and Bar", review_count: 400 }),
      row({ id: "e2", name: "Echelon Kitchen and Bar", review_count: 12 }),
      row({ id: "huna", name: "Hunã" }),
      row({ id: "other", name: "Third Place" }),
    ]);
    const dup = groups.find((g) => g.criterion === "address+geo");
    expect(dup?.rows.map((r) => r.id)).toEqual(["e1", "e2"]);
    const roof = groups.find((g) => g.criterion === "same-roof");
    expect(roof?.rows.map((r) => r.id).sort()).toEqual(["huna", "other"]);
  });

  it("a single leftover next to a duplicate pair makes no same-roof group", () => {
    const groups = groupDuplicates([
      row({ id: "e1", name: "Echelon" }),
      row({ id: "e2", name: "Echelon" }),
      row({ id: "huna", name: "Hunã" }),
    ]);
    expect(groups.map((g) => g.criterion)).toEqual(["address+geo"]);
  });

  it("place_id wins: a row already grouped by place_id is not regrouped", () => {
    const groups = groupDuplicates([
      row({ id: "a", google_place_id: "p1" }),
      row({ id: "b", google_place_id: "p1" }),
      row({ id: "c", google_place_id: "p2" }),
    ]);
    expect(groups).toHaveLength(1);
    expect(groups[0].criterion).toBe("place_id");
  });
});

describe("compareSurvivor", () => {
  it("an already-excluded row always loses", () => {
    const keep = row({ id: "keep", review_count: 1 });
    const gone = row({ id: "gone", review_count: 9999, excluded_reason: "duplicate_listing" });
    expect([gone, keep].sort(compareSurvivor)[0].id).toBe("keep");
  });

  it("a permanently closed listing loses to a live one", () => {
    const live = row({ id: "live", review_count: 1 });
    const dead = row({ id: "dead", review_count: 500, business_status: "CLOSED_PERMANENTLY" });
    expect([dead, live].sort(compareSurvivor)[0].id).toBe("live");
  });

  it("otherwise the listing people actually use (more reviews) survives", () => {
    const many = row({ id: "many", review_count: 1206 });
    const few = row({ id: "few", review_count: 1204 });
    expect([few, many].sort(compareSurvivor)[0].id).toBe("many");
  });

  it("ties break on richer columns, then on the older row", () => {
    const rich = row({ id: "rich", image_url: "http://x", created_at: "2026-09-01T00:00:00Z" });
    const bare = row({ id: "bare", created_at: "2026-01-01T00:00:00Z" });
    expect([bare, rich].sort(compareSurvivor)[0].id).toBe("rich");

    const old = row({ id: "old", created_at: "2026-01-01T00:00:00Z" });
    const recent = row({ id: "recent", created_at: "2026-09-01T00:00:00Z" });
    expect([recent, old].sort(compareSurvivor)[0].id).toBe("old");
  });
});

describe("isResolved", () => {
  it("a group with one live row and one excluded row needs no action", () => {
    expect(isResolved({
      criterion: "place_id",
      spreadMeters: 0,
      rows: [row({ id: "a" }), row({ id: "b", excluded_reason: "duplicate_listing" })],
    })).toBe(true);
  });

  it("two live rows still need a decision", () => {
    expect(isResolved({
      criterion: "place_id",
      spreadMeters: 0,
      rows: [row({ id: "a" }), row({ id: "b" })],
    })).toBe(false);
  });
});
