import { describe, expect, it } from "vitest";
import type { Venue } from "@/types";
import { detectUserLanguage, groundPlanBlock } from "./plan-grounding";

const v = (id: string, slug: string, name: string) => ({ id, slug, name }) as Venue;
const shortlist = [v("uuid-1", "sugar-rooftop", "Sugar Rooftop"), v("uuid-2", "e11even-miami", "E11EVEN Miami")];

describe("groundPlanBlock", () => {
  it("replaces a slug-in-the-id-field with the real UUID", () => {
    const out = JSON.parse(groundPlanBlock(JSON.stringify({ stops: [{ venueId: "sugar-rooftop", venueSlug: "sugar-rooftop", venueName: "Sugar" }] }), shortlist));
    expect(out.stops[0]).toMatchObject({ venueId: "uuid-1", venueSlug: "sugar-rooftop", venueName: "Sugar Rooftop" });
  });

  it("re-anchors by case-insensitive name when id and slug are both wrong", () => {
    const out = JSON.parse(groundPlanBlock(JSON.stringify({ stops: [{ venueId: "x", venueSlug: "eleven", venueName: "e11even miami" }] }), shortlist));
    expect(out.stops[0].venueId).toBe("uuid-2");
  });

  it("leaves an unmatched stop and non-JSON input untouched", () => {
    const stop = { venueId: "nope", venueSlug: "nope", venueName: "Nope Bar" };
    expect(JSON.parse(groundPlanBlock(JSON.stringify({ stops: [stop] }), shortlist)).stops[0]).toEqual(stop);
    expect(groundPlanBlock("not json {", shortlist)).toBe("not json {");
  });
});

describe("detectUserLanguage", () => {
  it("spots Spanish from accents or common words, English otherwise", () => {
    expect(detectUserLanguage("Dónde hay reggaetón en Wynwood hoy, somos 5")).toBe("es");
    expect(detectUserLanguage("Rooftop con vista para un cumpleanos")).toBe("es");
    expect(detectUserLanguage("Plan a chill first date in Brickell tonight")).toBe("en");
    expect(detectUserLanguage("plan something")).toBe("en");
  });
});
