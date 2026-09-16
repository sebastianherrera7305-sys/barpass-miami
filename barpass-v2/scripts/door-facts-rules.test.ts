import { describe, it, expect } from "vitest";
import {
  detectCover, detectDressCode, detectAgePolicy, hasDoorFactSignal,
  quoteAppearsInText, doorFactLinks, doorFactsPrompt,
} from "./door-facts-rules";

describe("detectCover", () => {
  it("reads a plain cover", () => {
    expect(detectCover("Doors at 10PM. $10 cover.")).toMatchObject({ men: 10, women: 10, conditional: false });
    expect(detectCover("Cover charge: $20")).toMatchObject({ men: 20, women: 20 });
    expect(detectCover("Admission $15 at the door")).toMatchObject({ men: 15, women: 15 });
    expect(detectCover("Entry fee is $5.00 after 9pm")?.men).toBe(5);
  });

  it('treats "no cover" as the number 0, not as missing data', () => {
    expect(detectCover("No cover, ever.")).toMatchObject({ men: 0, women: 0, conditional: false });
    expect(detectCover("Free admission all night")).toMatchObject({ men: 0, women: 0 });
    expect(detectCover("There is never a cover charge at Kilroy's")).toMatchObject({ men: 0, women: 0 });
  });

  it("splits a gendered door price", () => {
    expect(detectCover("Cover: men $20, ladies $10")).toMatchObject({ men: 20, women: 10 });
    expect(detectCover("Cover charge $25 for men and $15 for women")).toMatchObject({ men: 25, women: 15 });
    expect(detectCover("Ladies free, guys $10 cover")).toMatchObject({ men: 10, women: 0 });
  });

  it('flags a conditional free entry instead of writing cover_women = 0', () => {
    const f = detectCover("Ladies free before 11, $20 cover after");
    expect(f?.women).toBe(0);
    expect(f?.conditional).toBe(true);           // caller must NOT write this
    expect(detectCover("No cover with RSVP on the guest list")?.conditional).toBe(true);
  });

  it("keeps the literal sentence as evidence", () => {
    expect(detectCover("Live DJ nightly.\n$10 cover on Saturdays.\nKitchen open late.")?.evidence)
      .toBe("$10 cover on Saturdays.");
  });

  // ---- the ones that must return null ----
  it("a cover BAND is not a cover charge", () => {
    expect(detectCover("Saturday: The Landsharks, a Jimmy Buffett cover band. $12 burgers all night.")).toBeNull();
    expect(detectCover("The band covers classics from the 70s and 80s")).toBeNull();
    expect(detectCover("Our DJ covers hip hop, house and top 40 hits")).toBeNull();
  });

  it("ignores the word cover when it is not about the door", () => {
    expect(detectCover("Enjoy our covered patio with 12 TVs")).toBeNull();
    expect(detectCover("Need a place for game day? We've got you covered.")).toBeNull();
    expect(detectCover("Our insurance coverage is up to date")).toBeNull();
    expect(detectCover("We cover the Gators, the Jags and the Heat on 20 screens")).toBeNull();
  });

  it("never turns a food or drink price into a cover", () => {
    expect(detectCover("Wings $12, burgers $14, domestic drafts $4")).toBeNull();
    expect(detectCover("Bottle service starts at $500 for the table")).toBeNull();
    expect(detectCover("Happy hour 4-7pm, $5 wells")).toBeNull();
  });

  it("refuses an out-of-range or fractional amount", () => {
    expect(detectCover("Cover charge $2500 for the private room")).toBeNull();
    expect(detectCover("Cover $12.50")).toBeNull();
  });

  it("says nothing about a page that says nothing", () => {
    expect(detectCover("Open daily 11am-2am. Kitchen until midnight. Come as you are.")).toBeNull();
  });
});

describe("detectDressCode", () => {
  it("copies the venue's own words", () => {
    expect(detectDressCode("Dress code: no hats, no athletic wear.")?.value).toBe("no hats, no athletic wear.");
    expect(detectDressCode("Dress to impress. No exceptions.")?.value).toMatch(/dress to impress/i);
    expect(detectDressCode("Collared shirts required for gentlemen")?.value).toMatch(/collared shirts required/i);
    expect(detectDressCode("We enforce a business casual dress code on Fridays")?.value).toMatch(/business casual/i);
  });

  it('keeps the rule when it sits BEFORE the words "dress code" (Barsecco Miami, first dry run)', () => {
    expect(detectDressCode("Casual-Formal Dress code enforced after 7 pm every day.")?.value)
      .toBe("Casual-Formal Dress code enforced after 7 pm every day.");
  });

  it('"dress to impress" inside marketing prose is not a door rule (American Social Miami, first dry run)', () => {
    expect(detectDressCode("All private rooms have their own bar, so bring the cheer, unwind, shoot the breeze or dress to impress.")).toBeNull();
    expect(detectDressCode("Come dressy or come casual, we just want you to have a great time on our patio tonight")).toBeNull();
  });

  it("a stated absence of a dress code is still the venue's words", () => {
    expect(detectDressCode("No dress code — come as you are.")?.value).toMatch(/come as you are/i);
  });

  it("does not confuse clothing words with a door rule", () => {
    expect(detectDressCode("Ask about our house salad dressing")).toBeNull();
    expect(detectDressCode("The band dressed as pirates for Halloween")).toBeNull();
    expect(detectDressCode("Private dressing rooms for performers")).toBeNull();
    expect(detectDressCode("Open late, great cocktails, friendly staff")).toBeNull();
  });
});

describe("detectAgePolicy", () => {
  it("reads a published 21+ policy", () => {
    expect(detectAgePolicy("21+ with valid ID after 9pm")).toMatchObject({ value: "21+" });
    expect(detectAgePolicy("You must be 21 and over to enter")).toMatchObject({ value: "21+" });
    expect(detectAgePolicy("Must be 21 to enter. No exceptions.")).toMatchObject({ value: "21+" });
  });

  it("reads 18+ and the 18-to-enter / 21-to-drink split", () => {
    expect(detectAgePolicy("18 and over welcome every Thursday")).toMatchObject({ value: "18+" });
    expect(detectAgePolicy("18 to enter, 21 to drink")).toMatchObject({ value: "mixed" });
    expect(detectAgePolicy("Thursdays are 18+ to enter and 21+ to drink")).toMatchObject({ value: "mixed" });
  });

  it("the drinking age in a promo footer is not a door policy (Applebee's Gainesville, first dry run)", () => {
    expect(detectAgePolicy("Order To Go Must be 21+. Void where prohibited. Tax & gratuity excluded. Dine-in only.")).toBeNull();
    expect(detectAgePolicy("Must be 21+.")).toBeNull();
    expect(detectAgePolicy("You must be 21 to drink alcohol. Please drink responsibly.")).toBeNull();
    expect(detectAgePolicy("$6 margaritas all October. Must be 21 and over. While supplies last.")).toBeNull();
  });

  it("an age gate on SHIPPING is not a door policy (Bayside Cigars, first Miami dry run)", () => {
    expect(detectAgePolicy("Due to legal regulations, we can only ship cigars and tobacco products to customers aged 21 or older.")).toBeNull();
    expect(detectAgePolicy("You must be 21 and over to order online.")).toBeNull();
  });

  it("numbers that are not ages", () => {
    expect(detectAgePolicy("21 beers on tap and 18 TVs")).toBeNull();
    expect(detectAgePolicy("18% gratuity added to parties of 6 or more")).toBeNull();
    expect(detectAgePolicy("Serving Gainesville for 21 years in business")).toBeNull();
    expect(detectAgePolicy("Open 7 days. Happy hour 4-7.")).toBeNull();
  });

  it("refuses to pick one when the page contradicts itself", () => {
    expect(detectAgePolicy("Fridays are 21 and over.\nSaturdays are 18 and over.")).toBeNull();
    expect(detectAgePolicy("21 and over. 18 and up welcome.")).toBeNull();
  });
});

describe("hasDoorFactSignal", () => {
  it("is the cheap gate before paying for a model call", () => {
    expect(hasDoorFactSignal("$10 cover tonight")).toBe(true);
    expect(hasDoorFactSignal("Dress code enforced")).toBe(true);
    expect(hasDoorFactSignal("21+ only")).toBe(true);
    expect(hasDoorFactSignal("Wings, beer, football. Open at noon.")).toBe(false);
  });
});

describe("quoteAppearsInText", () => {
  const page = "Doors  at 10PM.\n$10 cover on\nSaturdays. 21+ with ID.";
  it("accepts a verbatim quote across whitespace differences", () => {
    expect(quoteAppearsInText(page, "$10 cover on Saturdays.")).toBe(true);
    expect(quoteAppearsInText(page, "doors at 10pm")).toBe(true);
  });
  it("rejects anything the page does not actually say", () => {
    expect(quoteAppearsInText(page, "$20 cover on Saturdays.")).toBe(false);
    expect(quoteAppearsInText(page, "Dress to impress")).toBe(false);
    expect(quoteAppearsInText(page, "21+")).toBe(false); // too short to be evidence
    expect(quoteAppearsInText(page, undefined)).toBe(false);
  });
});

describe("doorFactLinks", () => {
  const html = `<a href="/food-menu">Menu</a><a href="/info">Info</a>
    <a href="https://other.com/faq">FAQ</a><a href="/style.css">x</a><a href="/vip-tables">VIP Tables</a>`;
  it("keeps same-origin info pages and drops assets and other hosts", () => {
    const got = doorFactLinks(html, "https://bar.example/");
    expect(got).toContain("https://bar.example/info");
    expect(got).toContain("https://bar.example/vip-tables");
    expect(got.some((u) => u.includes("other.com") || u.endsWith(".css"))).toBe(false);
  });
});

describe("doorFactsPrompt", () => {
  it("pins the never-invent clauses the whole extractor rests on", () => {
    const p = doorFactsPrompt({ name: "X", type: "bar", city: "Gainesville" }, "body");
    expect(p).toMatch(/VERBATIM/);
    expect(p).toMatch(/Never guess/i);
    expect(p).toMatch(/cover band/i);
    expect(p).toContain("body");
  });
});
