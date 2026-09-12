import { describe, it, expect } from "vitest";
import {
  happyHourEnd,
  priceAppearsInText,
  sanitizeDrinks,
  pickTopDrinks,
  htmlToText,
  menuLinks,
  extractionPrompt,
} from "./drink-menu-rules";

describe("happyHourEnd", () => {
  it("reads a plain evening window", () => {
    expect(happyHourEnd("4-7pm")).toBe("19:00");
    expect(happyHourEnd("Mon-Fri 3pm - 7pm")).toBe("19:00");
    expect(happyHourEnd("4:00PM - 7:00PM")).toBe("19:00");
    expect(happyHourEnd("3-5:30pm")).toBe("17:30");
    expect(happyHourEnd("until 5 PM")).toBe("17:00");
    expect(happyHourEnd("open-4pm")).toBe("16:00");
    expect(happyHourEnd("4 Til 8")).toBe("20:00");
  });

  it("takes am/pm literally when it is there", () => {
    expect(happyHourEnd("11am-2pm")).toBe("14:00");
    expect(happyHourEnd("11:00 AM - 06:00 PM")).toBe("18:00");
    expect(happyHourEnd("12pm - 4pm")).toBe("16:00");
    expect(happyHourEnd("Sat–Sun 1p–4p")).toBe("16:00");
    expect(happyHourEnd("10am - 8pm")).toBe("20:00");
  });

  it("12am is midnight, not noon (was written as 12:00 for two State College bars)", () => {
    expect(happyHourEnd("10pm-12am")).toBe("00:00");
    expect(happyHourEnd("9:00pm-12:00am")).toBe("00:00");
    expect(happyHourEnd("until midnight")).toBe("00:00");
  });

  it("a bare 8-10 at a bar is evening, not morning (was written as 10:00)", () => {
    expect(happyHourEnd("8-10")).toBe("22:00");
    expect(happyHourEnd("Sun, Tues-Thurs 8-10")).toBe("22:00");
    expect(happyHourEnd("M-F 4-8")).toBe("20:00");
  });

  it("an end after an am start with no suffix rolls to pm", () => {
    expect(happyHourEnd("11am-2")).toBe("14:00");
  });

  it("refuses a window that ends at close (was written as the START time)", () => {
    expect(happyHourEnd("9PM-Close")).toBeNull();
    expect(happyHourEnd("10pm-close")).toBeNull();
    expect(happyHourEnd("5pm til late")).toBeNull();
  });

  it("accepts several windows only when they all end at the same time", () => {
    expect(happyHourEnd("Monday-Friday, Saturday & Sunday 3-8pm, 12-8pm")).toBe("20:00");
    expect(happyHourEnd("3-7PM 3-7PM")).toBe("19:00");
    expect(happyHourEnd("Mon-Fri 3-6pm | Sat-Sun 4-7pm")).toBeNull();
  });

  it("refuses multi-window strings instead of picking one number", () => {
    expect(happyHourEnd("3PM-5:30 PM | 9PM-Close")).toBeNull();
    expect(happyHourEnd("Mon-Fri 4:00pm-7:00pm; Sat 11:00am-4:00pm")).toBeNull();
    expect(happyHourEnd("3:00 pm - 7:00 pm, 10:00 pm - 11:00 pm")).toBeNull();
    expect(happyHourEnd("5PM-6PM, 6PM-7PM, 7:30PM")).toBeNull();
  });

  it("does not read '7 days a week' as a clock time", () => {
    expect(happyHourEnd("7 DAYS A WEEK 3pm to 8pm")).toBe("20:00");
  });

  it("returns null for nothing", () => {
    expect(happyHourEnd("")).toBeNull();
    expect(happyHourEnd(null)).toBeNull();
    expect(happyHourEnd("daily")).toBeNull();
  });
});

describe("priceAppearsInText", () => {
  it("accepts the usual printed forms", () => {
    expect(priceAppearsInText("Espresso Martini $18", 18)).toBe(true);
    expect(priceAppearsInText("Espresso Martini $ 18", 18)).toBe(true);
    expect(priceAppearsInText("Espresso Martini $18.00", 18)).toBe(true);
    expect(priceAppearsInText("Espresso Martini 18.00", 18)).toBe(true);
    expect(priceAppearsInText("Draft $6.50", 6.5)).toBe(true);
    expect(priceAppearsInText("Twin Peaks Drafts $3.25", 3.25)).toBe(true);
    expect(priceAppearsInText("6 dollars", 6)).toBe(true);
  });

  it("does not accept a longer number that merely contains the digits", () => {
    expect(priceAppearsInText("Bottle $60", 6)).toBe(false);
    expect(priceAppearsInText("Bottle $16.00", 6)).toBe(false);
    expect(priceAppearsInText("Draft $6.50", 6)).toBe(false);
    expect(priceAppearsInText("Draft $65", 6.5)).toBe(false);
    expect(priceAppearsInText("Draft $6", 60)).toBe(false);
  });

  it("accepts a bare number only next to the drink's own name", () => {
    expect(priceAppearsInText("Sangria 6\nPBR + choice 6\nDaisy Cutter 5", 6, "Sangria")).toBe(true);
    expect(priceAppearsInText("Sangria 6\nPBR + choice 6\nDaisy Cutter 5", 5, "Half Acre Daisy Cutter")).toBe(false);
    expect(priceAppearsInText("Sangria 6\nHalf Acre Daisy Cutter 5", 5, "Half Acre Daisy Cutter")).toBe(true);
    expect(priceAppearsInText("Open 6 days a week", 6, "Margarita")).toBe(false);
    expect(priceAppearsInText("Open 6 days a week", 6)).toBe(false);
  });

  it("rejects nonsense", () => {
    expect(priceAppearsInText("$0", 0)).toBe(false);
    expect(priceAppearsInText("$6", NaN)).toBe(false);
  });
});

describe("sanitizeDrinks", () => {
  const text = "HAPPY HOUR\nHouse Margarita $8\nModelo $5\nOld Fashioned $14\nWings $12";

  it("keeps only rows whose price is printed in the text", () => {
    const out = sanitizeDrinks([
      { name: "House Margarita", price: 8, category: "cocktail" },
      { name: "Modelo", price: 5, category: "beer" },
      { name: "Old Fashioned", price: 14, category: "cocktail" },
      { name: "Invented Spritz", price: 11, category: "cocktail" }, // not on the page
      { name: "Old Fashioned", price: 14, category: "cocktail" },   // duplicate
    ], text);
    expect(out.map((d) => d.name)).toEqual(["House Margarita", "Modelo", "Old Fashioned"]);
  });

  it("drops $0, out-of-range and non-numeric prices, and unknown categories become other", () => {
    const out = sanitizeDrinks([
      { name: "Free water", price: 0, category: "other" },
      { name: "Bottle", price: 9999, category: "bottle" },
      { name: "Market fish", price: "market", category: "other" },
      { name: "Modelo", price: "5", category: "lager" },
    ], text);
    expect(out).toEqual([{ name: "Modelo", price: 5, category: "other" }]);
  });

  it("returns empty for anything that is not an array", () => {
    expect(sanitizeDrinks(null, text)).toEqual([]);
    expect(sanitizeDrinks("[]", text)).toEqual([]);
    expect(sanitizeDrinks({ drinks: [] }, text)).toEqual([]);
  });
});

describe("pickTopDrinks", () => {
  it("puts cocktails first and maps category to emoji", () => {
    const top = pickTopDrinks([
      { name: "Modelo", price: 5, category: "beer" },
      { name: "Margarita", price: 8, category: "cocktail" },
      { name: "Cab", price: 9, category: "wine" },
    ], 2);
    expect(top).toEqual([
      { name: "Margarita", price: 8, emoji: "🍸" },
      { name: "Modelo", price: 5, emoji: "🍺" },
    ]);
  });
});

describe("htmlToText / menuLinks", () => {
  const html = `<html><head><style>.x{}</style><script>var a=1;</script></head><body>
    <nav><a href="/">St. Pat's Bar &amp; Grill</a><link rel="stylesheet" href="/bar.css"><a href="/about">About</a><a href="/parties">Bar parties</a>
    <a href="/kitchen">Drinks list</a><a href="/food-menu">Food</a><a href="/menu">Menu</a><a href="/specials">Happy Hour</a>
    <a href="https://other.com/drinks">x</a><a href="/menu.pdf">PDF</a><a href="/assets/bar.css">Bar</a></nav>
    <ul><li>Margarita &amp; salt $8</li><li>Modelo&nbsp;$5</li></ul></body></html>`;

  it("strips markup and keeps line breaks between items", () => {
    const t = htmlToText(html);
    expect(t).toContain("Margarita & salt $8");
    expect(t).toContain("Modelo $5");
    expect(t).not.toContain("var a=1");
    expect(t.split("\n").length).toBeGreaterThan(1);
  });

  it("keeps same-origin menu-looking links: drinks/happy hour first, food last, label-only matches after href matches, never the page itself or assets", () => {
    expect(menuLinks(html, "https://bar.example/")).toEqual([
      "https://bar.example/specials",
      "https://bar.example/menu",
      "https://bar.example/food-menu",
      "https://bar.example/kitchen",
    ]);
  });

  it("does not let a venue name containing 'bar' turn every link into a menu link", () => {
    expect(menuLinks(html, "https://bar.example/")).not.toContain("https://bar.example/parties");
    expect(menuLinks(html, "https://bar.example/")).not.toContain("https://bar.example/assets/bar.css");
  });

  it("treats /menus and /menus/ as one page", () => {
    // Astra Miami listed both; the same 20k-char menu was fetched twice and
    // ate the model's text budget, pushing a real page out.
    const dup = `<a href="/menus/">Menus</a><a href="/menus">Menu</a><a href="/drinks">Drinks</a>`;
    expect(menuLinks(dup, "https://astra.example/")).toEqual([
      "https://astra.example/drinks",
      "https://astra.example/menus/",
    ]);
  });

  it("respects the limit", () => {
    expect(menuLinks(html, "https://bar.example/", 1)).toEqual(["https://bar.example/specials"]);
  });
});

describe("extractionPrompt", () => {
  it("forbids guessing and asks for an empty answer when nothing is priced", () => {
    const p = extractionPrompt({ name: "X", type: "bar", city: "Miami" }, "text");
    expect(p).toMatch(/Never guess, infer, round, average, convert or estimate/);
    expect(p).toMatch(/\{"drinks":\[\],"happy_hour":null\}/);
    expect(p).toMatch(/Never food/);
    expect(p).toMatch(/heading directly above the list/);
  });

  it("bounds the page text it sends", () => {
    const p = extractionPrompt({ name: "X", type: "bar", city: "Miami" }, "a".repeat(20_000));
    expect(p.length).toBeLessThan(15_500);
  });
});
