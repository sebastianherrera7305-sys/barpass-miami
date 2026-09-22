import { describe, it, expect } from "vitest";
import {
  costOfRequest,
  estimateSweep,
  normalizeMask,
  rootField,
  tierOfField,
  USD_PER_1000,
} from "./places-pricing";
import { PlacesClient, DEFAULT_MAX_CALLS, type FetchLike } from "./places-client";

/** A fetch that records every call. If a dry run touches it, the test fails. */
function spyFetch(body: unknown = { id: "x" }) {
  const calls: string[] = [];
  const impl: FetchLike = async (url) => {
    calls.push(url);
    return { ok: true, status: 200, json: async () => body, text: async () => "" };
  };
  return { impl, calls };
}

const quiet = { reportOnExit: false, log: () => {}, apiKey: "test-key" };

describe("field -> SKU tier", () => {
  it("classifies the fields the sweep scripts actually asked for", () => {
    expect(tierOfField("types")).toBe("essentials");
    expect(tierOfField("primaryType")).toBe("pro");
    expect(tierOfField("priceLevel")).toBe("enterprise");
    expect(tierOfField("regularOpeningHours")).toBe("enterprise");
    expect(tierOfField("servesBeer")).toBe("atmosphere");
    expect(tierOfField("servesCocktails")).toBe("atmosphere");
    expect(tierOfField("editorialSummary")).toBe("atmosphere");
  });

  it("bills a sub-field at its parent's tier", () => {
    // backfill-venue-hours.ts asks for exactly this string.
    expect(rootField("regularOpeningHours.periods")).toBe("regularOpeningHours");
    expect(tierOfField("regularOpeningHours.periods")).toBe("enterprise");
    expect(tierOfField("photos.name")).toBe("idsOnly");
  });

  it("strips the places. prefix that Text Search masks carry", () => {
    expect(rootField("places.id")).toBe("id");
    expect(normalizeMask("places.id,places.displayName")).toEqual(["id", "displayName"]);
  });

  it("knows the photo LIST is free and does not confuse it with photo bytes", () => {
    // fix-venue-photos.ts asks only for `photos`; that mask costs nothing.
    // The money in that script is the separate media download.
    expect(tierOfField("photos")).toBe("idsOnly");
    expect(costOfRequest("details", "photos").usd).toBe(0);
    expect(costOfRequest("photo").usd).toBeCloseTo(USD_PER_1000.photo.idsOnly / 1000, 10);
  });

  it("bills an unrecognised field at the dearest tier, and says so", () => {
    // A field we have never seen must never be silently free — that is how a
    // sweep gets mispriced. Over-estimate, and surface the name.
    const cost = costOfRequest("details", "id,someFieldGoogleAddedLastWeek");
    expect(cost.tier).toBe("atmosphere");
    expect(cost.unknownFields).toEqual(["someFieldGoogleAddedLastWeek"]);
  });
});

describe("cost of a request", () => {
  it("bills ONCE at the highest tier, not once per tier", () => {
    // The correction to the 2026-09-14 diagnosis. A mask spanning Essentials +
    // Pro + Enterprise + Atmosphere is one Atmosphere charge ($25/1k), not the
    // $67/1k sum of the four. Verified against Google's usage-and-billing page.
    const wide = "id,types,primaryType,priceLevel,regularOpeningHours,servesBeer";
    const cost = costOfRequest("details", wide);
    expect(cost.tier).toBe("atmosphere");
    expect(cost.usd).toBeCloseTo(0.025, 10);
  });

  it("prices each sweep script's real field mask", () => {
    expect(costOfRequest("details", "regularOpeningHours.periods").tier).toBe("enterprise");
    expect(costOfRequest("details", "primaryType,types,servesBeer,servesWine,servesCocktails").tier)
      .toBe("atmosphere");
    expect(costOfRequest("details", "id,priceLevel").tier).toBe("enterprise");
    expect(costOfRequest("details", "photos").tier).toBe("idsOnly");
  });

  it("reconstructs the 14 Sept sweep: five narrow passes vs one merged call", () => {
    // The five Place Details masks that ran over the same venues that day.
    const passes = [
      "regularOpeningHours.periods",                                  // backfill-venue-hours
      "primaryType,types,servesBeer,servesWine,servesCocktails",      // fix-venue-types
      "id,priceLevel",                                                // fix-price-tiers
      "photos",                                                       // fix-venue-photos
      "id,displayName,businessStatus,rating,userRatingCount,websiteUri," +
        "nationalPhoneNumber,regularOpeningHours.periods,photos.name", // refresh-venue-core-data
    ];
    const venues = 2510;
    const separate = passes.reduce((sum, m) => sum + estimateSweep("details", m, venues).usd, 0);
    const merged = estimateSweep("details", passes.join(","), venues);

    expect(separate).toBeCloseTo(213.35, 2); // 20 + 25 + 20 + 0 + 20 = $85/1k
    expect(merged.tier).toBe("atmosphere");
    expect(merged.usd).toBeCloseTo(62.75, 2); // one Atmosphere charge, $25/1k
    expect(separate - merged.usd).toBeCloseTo(150.6, 2);
  });

  it("prices a full-catalogue sweep of all 4,417 venues", () => {
    const all = estimateSweep("details", "id,priceLevel,servesBeer", 4417);
    expect(all.usd).toBeCloseTo(110.43, 2);
  });
});

describe("dry run", () => {
  it("is the default — nobody has to remember a flag to be safe", () => {
    // The DEFAULT is what is under test, so the runner's own environment must
    // not get a vote. Remove PLACES_SPEND and put it back.
    const previous = process.env.PLACES_SPEND;
    delete process.env.PLACES_SPEND;
    try {
      expect(new PlacesClient(quiet).isDryRun).toBe(true);
    } finally {
      if (previous !== undefined) process.env.PLACES_SPEND = previous;
    }
  });

  it("makes NO network call at all, and still prices the run", async () => {
    const { impl, calls } = spyFetch();
    const client = new PlacesClient({ ...quiet, fetchImpl: impl });

    for (const id of ["a", "b", "c"]) {
      const res = await client.placeDetails(id, "id,priceLevel,servesBeer");
      expect(res.status).toBe("dryRun");
    }

    expect(calls).toHaveLength(0);              // the whole point
    expect(client.stats.callsIssued).toBe(3);
    expect(client.stats.estimatedUsd).toBeCloseTo(0.075, 10); // 3 x $25/1k
    expect(client.report()).toContain("DRY RUN");
  });

  it("spends only when spending is asked for explicitly", async () => {
    const { impl, calls } = spyFetch();
    const client = new PlacesClient({ ...quiet, spend: true, fetchImpl: impl });
    const res = await client.placeDetails("a", "id");
    expect(res.status).toBe("ok");
    expect(calls).toHaveLength(1);
  });
});

describe("hard cap", () => {
  it("stops at the cap and reports how many it refused", async () => {
    const { impl, calls } = spyFetch();
    const client = new PlacesClient({ ...quiet, spend: true, maxCalls: 3, fetchImpl: impl });

    const results = [];
    for (const id of ["a", "b", "c", "d", "e"]) {
      results.push((await client.placeDetails(id, "id,priceLevel")).status);
    }

    expect(results).toEqual(["ok", "ok", "ok", "capped", "capped"]);
    expect(calls).toHaveLength(3);
    expect(client.stats.cappedCalls).toBe(2);
    expect(client.report()).toContain("2 call(s) were refused");
  });

  it("caps the dry run too, so an estimate cannot run away either", async () => {
    const { impl, calls } = spyFetch();
    const client = new PlacesClient({ ...quiet, maxCalls: 2, fetchImpl: impl });
    for (const id of ["a", "b", "c"]) await client.placeDetails(id, "id");
    expect(calls).toHaveLength(0);
    expect(client.stats.cappedCalls).toBe(1);
  });

  it("defaults to a cap that clears one full catalogue pass of 4,417", () => {
    expect(DEFAULT_MAX_CALLS).toBeGreaterThan(4417);
  });
});

describe("per-run cache", () => {
  it("fetches one place once, however many callers ask", async () => {
    const { impl, calls } = spyFetch();
    const client = new PlacesClient({ ...quiet, spend: true, fetchImpl: impl });

    await client.placeDetails("same-id", "id,priceLevel");
    const second = await client.placeDetails("same-id", "priceLevel");

    expect(calls).toHaveLength(1);
    expect(second).toMatchObject({ status: "ok", cached: true });
    expect(client.stats.cacheHits).toBe(1);
    expect(client.stats.estimatedUsd).toBeCloseTo(0.02, 10); // billed once
  });

  it("refetches when the second caller wants a field the first never asked for", async () => {
    // Serving a cached response that is missing the caller's field would write
    // an empty value into the catalogue — worse than paying twice. So: refetch,
    // and count it, because this pattern IS the 2026-09-14 bug.
    const { impl, calls } = spyFetch();
    const client = new PlacesClient({ ...quiet, spend: true, fetchImpl: impl });

    await client.placeDetails("same-id", "id");
    await client.placeDetails("same-id", "id,servesBeer");

    expect(calls).toHaveLength(2);
    expect(client.stats.remasked).toBe(1);
    expect(client.report()).toContain("Merge those masks");
  });
});

describe("the report", () => {
  it("names the price source and calls itself an estimate", () => {
    const client = new PlacesClient({ ...quiet, label: "backfill-venue-hours" });
    const text = client.report();
    expect(text).toContain("backfill-venue-hours");
    expect(text).toContain("not an invoice");
    expect(text).toContain("developers.google.com/maps/billing-and-pricing/pricing");
  });

  it("prints once, however many times it is asked to", () => {
    const lines: string[] = [];
    const client = new PlacesClient({ ...quiet, log: (l: string) => lines.push(l), reportOnExit: false });
    client.printReport();
    client.printReport();
    expect(lines).toHaveLength(1);
  });
});
