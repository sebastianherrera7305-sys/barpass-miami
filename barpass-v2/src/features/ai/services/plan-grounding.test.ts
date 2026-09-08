import { describe, expect, it } from "vitest";
import type { Venue } from "@/types";
import { detectUserLanguage, groundPlanBlock } from "./plan-grounding";

const v = (id: string, slug: string, name: string) => ({ id, slug, name }) as Venue;
const shortlist = [v("uuid-1", "sugar-rooftop", "Sugar Rooftop"), v("uuid-2", "e11even-miami", "E11EVEN Miami")];

describe("groundPlanBlock", () => {
  it("replaces a slug-in-the-id-field with the real UUID", () => {
    const out = JSON.parse(groundPlanBlock(JSON.stringify({ stops: [{ venueId: "sugar-rooftop", venueSlug: "sugar-rooftop", venueName: "Sugar" }] }), shortlist)!);
    expect(out.stops[0]).toMatchObject({ venueId: "uuid-1", venueSlug: "sugar-rooftop", venueName: "Sugar Rooftop" });
  });

  it("re-anchors by case-insensitive name when id and slug are both wrong", () => {
    const out = JSON.parse(groundPlanBlock(JSON.stringify({ stops: [{ venueId: "x", venueSlug: "eleven", venueName: "e11even miami" }] }), shortlist)!);
    expect(out.stops[0].venueId).toBe("uuid-2");
  });

  it("strips bold markers from the card's text fields", () => {
    const out = JSON.parse(groundPlanBlock(JSON.stringify({ title: "**Noche**", summary: "x", insiderTip: "**tip**", stops: [{ venueId: "uuid-1", note: "pide el **mezcal**" }] }), shortlist)!);
    expect(out.title).toBe("Noche");
    expect(out.insiderTip).toBe("tip");
    expect(out.stops[0].note).toBe("pide el mezcal");
  });

  it("drops an invented stop and the whole block when nothing survives", () => {
    // 2026-09-08 production: a plan contained "South Beach Strip", a venue
    // that doesn't exist — the app would render a card that goes nowhere.
    const fake = { venueId: "nope", venueSlug: "nope", venueName: "Nope Bar", estimatedSpend: 30 };
    const real = { venueId: "uuid-1", venueSlug: "sugar-rooftop", venueName: "Sugar Rooftop", estimatedSpend: 40 };
    const mixed = JSON.parse(groundPlanBlock(JSON.stringify({ totalEstimate: 70, stops: [real, fake] }), shortlist)!);
    expect(mixed.stops).toHaveLength(1);
    expect(mixed.stops[0].venueId).toBe("uuid-1");
    expect(mixed.totalEstimate).toBe(40);
    expect(groundPlanBlock(JSON.stringify({ stops: [fake] }), shortlist)).toBeNull();
    expect(groundPlanBlock("not json {", shortlist)).toBe("not json {");
  });
});

describe("detectUserLanguage", () => {
  it("spots Spanish from accents or common words, English otherwise", () => {
    expect(detectUserLanguage("Dónde hay reggaetón en Wynwood hoy, somos 5")).toBe("es");
    expect(detectUserLanguage("Rooftop con vista para un cumpleanos")).toBe("es");
    expect(detectUserLanguage("Plan a chill first date in Brickell tonight")).toBe("en");
    expect(detectUserLanguage("plan something")).toBe("en");
    // 2026-09-08: this answered in English because a 0-0 tie defaulted to it.
    expect(detectUserLanguage("llevame a e11even")).toBe("es");
    expect(detectUserLanguage("quiero ir a space")).toBe("es");
  });

  it("returns null when there is genuinely no signal, so no language is forced", () => {
    expect(detectUserLanguage("space")).toBeNull();
    expect(detectUserLanguage("ok")).toBeNull();
  });
});
