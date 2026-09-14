import { describe, expect, it } from "vitest";
import type { Venue } from "@/types";
import { createReplyTransform, sanitizeProse } from "./reply-stream";

const v = (id: string, slug: string, name: string) => ({ id, slug, name }) as Venue;
const shortlist = [v("uuid-1", "sugar-rooftop", "Sugar Rooftop"), v("uuid-2", "amor-miami", "Amor Miami")];

const plan = (over: Record<string, unknown> = {}, stopOver: Record<string, unknown> = {}) =>
  JSON.stringify({
    title: "Noche Wynwood",
    summary: "De la terraza a la pista.",
    stops: [
      {
        time: "10:30 PM",
        venueId: "uuid-1",
        venueSlug: "sugar-rooftop",
        venueName: "Sugar Rooftop",
        note: "Pide el mezcal antes de las 11.",
        estimatedSpend: 40,
        ...stopOver,
      },
    ],
    totalEstimate: 40,
    insiderTip: "Llega temprano, la fila se pone fea.",
    ...over,
  });

/** Feed a whole reply through in one piece and return what a client sees. */
function run(reply: string, pieces = 1): { out: string; drops: string[] } {
  const drops: string[] = [];
  const t = createReplyTransform({ shortlist, onDrop: (r) => drops.push(r) });
  let out = "";
  const size = Math.ceil(reply.length / pieces);
  for (let i = 0; i < reply.length; i += size) out += t.push(reply.slice(i, i + size));
  out += t.flush();
  return { out, drops };
}

/** The web's own parser — the thing that decides card vs. wall of JSON. */
const PLAN_FENCE = /```json\s*([\s\S]*?)```\s*$/;
const OPTIONS_FENCE = /```options\s*([\s\S]*?)```\s*$/;

describe("sanitizeProse", () => {
  it("strips the markdown the model emits despite the plain-text rule", () => {
    expect(sanitizeProse("- 9:45 PM: 1-800-Lucky  \n- 10:30 PM: **Amor**")).toBe("9:45 PM: 1-800-Lucky\n10:30 PM: Amor");
  });

  it("leaves a hyphen that isn't a bullet alone", () => {
    expect(sanitizeProse("Abre 9-11 PM, ve a 1-800-Lucky")).toBe("Abre 9-11 PM, ve a 1-800-Lucky");
  });

  it("drops heading marks", () => {
    expect(sanitizeProse("## Tonight\ntext")).toBe("Tonight\ntext");
  });
});

describe("createReplyTransform — the plan block always ends the message", () => {
  it("moves a sign-off written after the block back in front of it", () => {
    const { out } = run(`Aquí va tu noche:\n\n\`\`\`json\n${plan()}\n\`\`\`\n¡Que la disfrutes!`);
    expect(out).toMatch(PLAN_FENCE);
    expect(out).toContain("¡Que la disfrutes!");
    expect(out.indexOf("¡Que la disfrutes!")).toBeLessThan(out.indexOf("```json"));
  });

  it("survives being split across arbitrary stream chunks", () => {
    const reply = `Listo.\n\n\`\`\`json\n${plan()}\n\`\`\`\nDisfruta.`;
    for (const pieces of [1, 3, 7, 40, reply.length]) {
      const { out } = run(reply, pieces);
      const match = out.match(PLAN_FENCE);
      expect(match, `split into ${pieces} pieces`).not.toBeNull();
      expect(JSON.parse(match![1]).stops[0].venueId).toBe("uuid-1");
    }
  });
});

describe("createReplyTransform — a block the client can't render is never shown", () => {
  it("repairs a money field the model wrote as a string", () => {
    const { out, drops } = run(`Va:\n\`\`\`json\n${plan({ totalEstimate: "$40" }, { estimatedSpend: "40" })}\n\`\`\``);
    const match = out.match(PLAN_FENCE);
    expect(drops).toEqual([]);
    expect(JSON.parse(match![1])).toMatchObject({ totalEstimate: 40, stops: [{ estimatedSpend: 40 }] });
  });

  it("drops a plan that still fails the schema instead of dumping raw JSON", () => {
    const { out, drops } = run(`Va:\n\`\`\`json\n${plan({ insiderTip: "" })}\n\`\`\``);
    expect(out).not.toContain("```");
    expect(out).not.toContain("venueSlug");
    expect(out).toContain("Va:");
    expect(drops[0]).toMatch(/nightPlanSchema/);
  });

  it("drops a plan whose venues are all invented", () => {
    const { out, drops } = run(`Va:\n\`\`\`json\n${plan({}, { venueId: "nope", venueSlug: "south-beach-strip", venueName: "South Beach Strip" })}\n\`\`\``);
    expect(out).not.toContain("```");
    expect(drops[0]).toMatch(/grounding/);
  });

  it("drops a fence the stream ended in the middle of", () => {
    const { out, drops } = run(`Va:\n\`\`\`json\n{"title":"Noche","stops":[{"venueId":"uuid-1"`);
    expect(out.trim()).toBe("Va:");
    expect(drops[0]).toMatch(/open ```json fence/);
  });
});

describe("createReplyTransform — quick replies", () => {
  it("promotes an inline Options array to a real fence", () => {
    // Measured in production 2026-09-13 for the prompt "plan something".
    const { out } = run(`Got a vibe in mind? Weekend or weekday? Options: ["Weekend", "Weekday"]`);
    const match = out.match(OPTIONS_FENCE);
    expect(match).not.toBeNull();
    expect(JSON.parse(match![1])).toEqual(["Weekend", "Weekday"]);
    expect(out).not.toContain('Options: [');
    expect(out).toContain("Got a vibe in mind?");
  });

  it("recognises the Spanish spelling on its own line", () => {
    const { out } = run(`¿Qué buscas?\nOpciones: ["Rooftop", "Bailar"]`);
    expect(JSON.parse(out.match(OPTIONS_FENCE)![1])).toEqual(["Rooftop", "Bailar"]);
  });

  it("never streams half an inline array into the bubble", () => {
    const reply = `¿Qué buscas? Opciones: ["Rooftop", "Bailar"]`;
    for (const pieces of [2, 5, 11, reply.length]) {
      const { out } = run(reply, pieces);
      // The visible bubble is everything before the fence — no bracket, no
      // half-typed array, however the chunks happened to land.
      const prose = out.slice(0, out.indexOf("```options"));
      expect(prose.trim(), `split into ${pieces} pieces`).toBe("¿Qué buscas?");
      expect(JSON.parse(out.match(OPTIONS_FENCE)![1])).toEqual(["Rooftop", "Bailar"]);
    }
  });

  it("leaves prose alone when the array isn't parseable", () => {
    const { out } = run(`Options: [Weekend, Weekday]`);
    expect(out).toContain("Options: [Weekend, Weekday]");
  });

  it("caps chips at four", () => {
    const { out } = run('Pick:\n```options\n["a","b","c","d","e"]\n```');
    expect(JSON.parse(out.match(OPTIONS_FENCE)![1])).toEqual(["a", "b", "c", "d"]);
  });

  it("keeps the plan when the model sends both blocks", () => {
    const { out, drops } = run(`Va:\n\`\`\`options\n["x","y"]\n\`\`\`\n\`\`\`json\n${plan()}\n\`\`\``);
    expect(out).toMatch(PLAN_FENCE);
    expect(out).not.toContain("```options");
    expect(drops.some((d) => /both a plan and an options block/.test(d))).toBe(true);
  });
});

describe("createReplyTransform — plain replies", () => {
  it("passes ordinary prose through untouched", () => {
    const { out } = run("Astra Miami Rooftop, 2121 NW 2nd Ave. Llega a las 10.");
    expect(out).toBe("Astra Miami Rooftop, 2121 NW 2nd Ave. Llega a las 10.");
  });

  it("never emits a stray star when a token is exactly '**'", () => {
    const t = createReplyTransform({ shortlist });
    const out = t.push("Ve a ") + t.push("**") + t.push("Sugar Rooftop") + t.push("**") + t.push(" hoy") + t.flush();
    expect(out).toBe("Ve a Sugar Rooftop hoy");
  });
});
