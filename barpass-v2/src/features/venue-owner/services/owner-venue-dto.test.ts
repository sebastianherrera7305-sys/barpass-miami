import { describe, it, expect } from "vitest";
import {
  toWeeklyHours,
  listingVisibility,
  parseOwnerDrinks,
  toOwnerVenueDto,
  type OwnerVenueRow,
} from "./owner-venue-dto";

describe("toWeeklyHours", () => {
  it("returns null when hours are unknown, never seven closed days", () => {
    expect(toWeeklyHours(null)).toBeNull();
    expect(toWeeklyHours([])).toBeNull();
    expect(toWeeklyHours("not json")).toBeNull();
    expect(toWeeklyHours([{ day: 9, open: "20:00", close: "02:00" }])).toBeNull();
  });

  it("marks days with no period as closed and keeps the rest", () => {
    // Rush Nightclub's real shape: Friday and Saturday only.
    const week = toWeeklyHours([
      { day: 5, open: "20:00", close: "02:00" },
      { day: 6, open: "21:00", close: "02:00" },
    ]);
    expect(week).not.toBeNull();
    expect(week!).toHaveLength(7);
    const friday = week!.find((d) => d.day === 5)!;
    expect(friday.closed).toBe(false);
    expect(friday.periods).toEqual([{ open: "20:00", close: "02:00" }]);
    expect(week!.find((d) => d.day === 2)!.closed).toBe(true);
  });

  it("presents the week Monday-first with day 0 still meaning Sunday", () => {
    const week = toWeeklyHours([{ day: 0, open: "17:00", close: "23:00" }])!;
    expect(week.map((d) => d.day)).toEqual([1, 2, 3, 4, 5, 6, 0]);
    expect(week[6].label).toBe("Sunday");
    expect(week[6].periods).toEqual([{ open: "17:00", close: "23:00" }]);
  });

  it("keeps two periods on the same day", () => {
    const week = toWeeklyHours([
      { day: 3, open: "17:00", close: "20:00" },
      { day: 3, open: "22:00", close: "02:00" },
    ])!;
    expect(week.find((d) => d.day === 3)!.periods).toHaveLength(2);
  });

  it("accepts the JSON-string shape as well as jsonb", () => {
    const week = toWeeklyHours('[{"day":4,"open":"22:00","close":"03:00"}]')!;
    expect(week.find((d) => d.day === 4)!.periods[0].open).toBe("22:00");
  });
});

describe("listingVisibility", () => {
  it("treats a null business_status as unknown, not closed", () => {
    expect(listingVisibility({ business_status: null, excluded_reason: null })).toEqual({
      listed: true,
      reason: null,
      businessStatus: null,
    });
  });

  it("reports the exclusion reason verbatim", () => {
    const v = listingVisibility({
      excluded_reason: "Airport VIP lounge inside MIA, not a public nightlife venue",
      business_status: "OPERATIONAL",
    });
    expect(v.listed).toBe(false);
    expect(v.reason).toContain("Airport VIP lounge");
  });

  it("hides a permanently closed venue and says so", () => {
    const v = listingVisibility({ excluded_reason: null, business_status: "CLOSED_PERMANENTLY" });
    expect(v.listed).toBe(false);
    expect(v.reason).toMatch(/permanently closed/i);
  });
});

describe("parseOwnerDrinks", () => {
  it("drops items without a positive price instead of showing $0", () => {
    expect(parseOwnerDrinks([{ name: "Well vodka", price: 0 }, { name: "Mojito", price: 14 }])).toEqual([
      { name: "Mojito", price: 14, emoji: "🍸" },
    ]);
  });

  it("parses the legacy JSON-string column", () => {
    expect(parseOwnerDrinks('[{"name":"Draft","price":6,"emoji":"🍺"}]')).toEqual([
      { name: "Draft", price: 6, emoji: "🍺" },
    ]);
  });
});

const BASE_ROW: OwnerVenueRow = {
  id: "11111111-1111-1111-1111-111111111111",
  slug: "some-bar",
  name: "Some Bar",
  type: "bar",
  city: "Gainesville",
  neighborhood: "Midtown",
  address: "1 University Ave",
  phone: null,
  website: null,
  instagram_handle: null,
  image_url: null,
  age_policy: null,
  price_tier: 2,
  avg_spend: 0,
  cover_men: null,
  cover_women: null,
  open_time: "20:00",
  close_time: "02:00",
  happy_hour_until: null,
  dress_code: "",
  parking: "",
  timezone: "America/New_York",
  music_genres: null,
  vibes: null,
  hours: null,
  popular_drinks: [],
  field_sources: null,
  excluded_reason: null,
  business_status: null,
  google_synced_at: null,
};

describe("toOwnerVenueDto", () => {
  it("reads avg_spend = 0 as no data, not as free", () => {
    expect(toOwnerVenueDto(BASE_ROW).avgSpend).toBeNull();
    expect(toOwnerVenueDto({ ...BASE_ROW, avg_spend: 40 }).avgSpend).toBe(40);
  });

  it("normalises null arrays and empty strings without inventing content", () => {
    const dto = toOwnerVenueDto(BASE_ROW);
    expect(dto.musicGenres).toEqual([]);
    expect(dto.vibes).toEqual([]);
    expect(dto.dressCode).toBeNull();
    expect(dto.parking).toBeNull();
  });

  it("leaves unchecked amenities as null rather than false", () => {
    const dto = toOwnerVenueDto(BASE_ROW);
    expect(dto.amenities.outdoorSeating).toBeNull();
    const checked = toOwnerVenueDto({ ...BASE_ROW, outdoor_seating: false });
    expect(checked.amenities.outdoorSeating).toBe(false);
  });

  it("carries the drinks provenance through when there is one", () => {
    const dto = toOwnerVenueDto({
      ...BASE_ROW,
      popular_drinks: [{ name: "IPA", price: 7 }],
      field_sources: { popular_drinks: { url: "https://example.com/menu", date: "2026-09-12" } },
    });
    expect(dto.drinksSource).toEqual({ url: "https://example.com/menu", date: "2026-09-12" });
  });
});
