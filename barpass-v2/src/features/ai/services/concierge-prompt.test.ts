import { describe, expect, it } from "vitest";
import type { Venue } from "@/types";
import { buildConciergeSystemPrompt, isOpenAt, selectRelevantVenues } from "./concierge-prompt";

function venue(over: Partial<Venue> & { id: string }): Venue {
  return {
    slug: over.id, name: over.id, type: "bar", neighborhood: "Brickell", city: "Miami",
    address: "", lat: 25.76, lng: -80.19, hook: "", description: "", rating: 4, reviewCount: 10,
    coverMen: null, coverWomen: null, priceTier: 2, avgSpend: null,
    openTime: "20:00", closeTime: "03:00", happyHourUntil: null,
    musicGenres: [], vibes: [], dressCode: "", parking: "", crowdLevel: "steady",
    bestArrivalTime: "22:00", peakHours: "", popularDrinks: [], upcomingEvents: [],
    emoji: "🍸", imageUrl: null, instagramHandle: null, isTrending: false, isOpenNow: true,
    ...over,
  };
}

// 50 generic bars so the limit actually bites.
const filler = Array.from({ length: 50 }, (_, i) => venue({ id: `bar-${i}`, lat: 25.80 + i * 0.01 }));

describe("selectRelevantVenues", () => {
  it("keeps every venue of a type the user asked for, in Spanish or English", () => {
    const rooftops = Array.from({ length: 6 }, (_, i) => venue({ id: `roof-${i}`, type: "rooftop" }));
    const es = selectRelevantVenues([...filler, ...rooftops], "una terraza con vista para un cumpleaños", 20);
    const en = selectRelevantVenues([...filler, ...rooftops], "a rooftop with a view", 20);
    expect(es.filter((v) => v.type === "rooftop")).toHaveLength(6);
    expect(en.filter((v) => v.type === "rooftop")).toHaveLength(6);
  });

  it("treats 'Rooftop'/'Sky' in a venue's own name as rooftop evidence (catalog types them as bars)", () => {
    const sugar = venue({ id: "sugar", name: "Sugar Rooftop", type: "bar" });
    const rosa = venue({ id: "rosa", name: "Rosa Sky", type: "bar" });
    const out = selectRelevantVenues([...filler, sugar, rosa], "rooftop con vista para un cumpleaños", 10);
    expect(out.slice(0, 2).map((v) => v.id).sort()).toEqual(["rosa", "sugar"]);
  });

  it("never returns the venue the user is standing in", () => {
    const here = venue({ id: "here" });
    const out = selectRelevantVenues([here, ...filler], "qué hago después", 20, { excludeId: "here" });
    expect(out.find((v) => v.id === "here")).toBeUndefined();
  });

  it("ranks nearby venues above far ones when the user's location is known", () => {
    const near = venue({ id: "near", lat: 25.7601, lng: -80.1901 });
    const far = venue({ id: "far", lat: 26.2, lng: -80.19 });
    const out = selectRelevantVenues([far, ...filler, near], "algo para seguir", 10, { origin: { lat: 25.76, lng: -80.19 } });
    expect(out.map((v) => v.id)).toContain("near");
    expect(out.map((v) => v.id)).not.toContain("far");
  });

  it("sinks venues that are closed right now", () => {
    const closed = venue({ id: "closed", openTime: "11:00", closeTime: "17:00" });
    const out = selectRelevantVenues([closed, ...filler], "un bar ahora", 20, { nowMin: 23 * 60 });
    expect(out.map((v) => v.id)).not.toContain("closed");
  });

  it("still pins a venue the user named, even if everything else outscores it", () => {
    const named = venue({ id: "candela", name: "Candela Bar", openTime: "11:00", closeTime: "17:00" });
    const out = selectRelevantVenues([...filler, named], "quiero ir a candela bar", 10, { nowMin: 23 * 60 });
    expect(out.map((v) => v.id)).toContain("candela");
  });
});

describe("isOpenAt", () => {
  it("handles closing after midnight", () => {
    const v = { openTime: "22:00", closeTime: "05:00" };
    expect(isOpenAt(v, 23 * 60)).toBe(true);
    expect(isOpenAt(v, 2 * 60)).toBe(true);
    expect(isOpenAt(v, 12 * 60)).toBe(false);
  });
  it("treats unknown hours as open so a data gap never hides a venue", () => {
    expect(isOpenAt({ openTime: "", closeTime: "" }, 600)).toBe(true);
  });
});

describe("buildConciergeSystemPrompt", () => {
  it("tells the model where the user is and shows distances in the digest", () => {
    const here = venue({ id: "here", name: "Factory Town", neighborhood: "Wynwood" });
    const next = venue({ id: "next", name: "Next Spot", lat: 25.7701, lng: -80.19 });
    const prompt = buildConciergeSystemPrompt([next], { currentVenue: here, origin: { lat: 25.76, lng: -80.19 }, now: new Date("2026-09-07T03:00:00Z") });
    expect(prompt).toContain("The user is AT Factory Town");
    expect(prompt).toMatch(/km away, ~\d+ min ride/);
    expect(prompt).toContain("Never name a specific drink");
  });

  it("uses the venue city's timezone for RIGHT NOW", () => {
    const prompt = buildConciergeSystemPrompt([], { now: new Date("2026-09-07T03:00:00Z"), timeZone: "America/Chicago" });
    // 03:00Z is 10 PM in Chicago (CDT) and 11 PM in Miami.
    expect(prompt).toContain("10:00 PM");
  });
});
