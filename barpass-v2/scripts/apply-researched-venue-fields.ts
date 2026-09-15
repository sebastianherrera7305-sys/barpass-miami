/**
 * Writes venue fields that were established by hand, one venue at a time,
 * against a primary source — and records that source in `field_sources`.
 *
 * WHY THIS IS A TABLE AND NOT A SCRAPER
 * Everything below was read off the venue's own live page by a human/agent and
 * transcribed. The table is the audit trail: each entry names the exact URL it
 * came from and the date it was read, so a future pass can re-check the claim
 * instead of trusting it. Nothing is derived, guessed, or inferred from a
 * sibling venue. If a source published nothing, there is no entry — an empty
 * column is a fact, and the fabricated `music_genres` of 2026-09-01 is what
 * happens when that rule is broken.
 *
 * 2026-09-15 — Gainesville college-market audit, Midtown + Downtown.
 * Tampa's SunPubs Hospitality Group bought four Midtown bars and rebranded
 * them (The Social → MacDinton's, JJ's Tavern → Grove, Lil' Rudy's → Fats,
 * Rowdy Rudy's → Rowdy's; alligator.org 2026-06). Rowdy's and Fats publish NO
 * hours on Google, have no website, and their Linktrees carry only event
 * links. What they do have is an Instagram that posts every night's lineup —
 * and `venues.instagram_handle` was null on all 1846 rows even though the
 * venue page already renders it as a link (`getting-there.tsx`). So the
 * honest, useful write for these venues is the handle, not invented hours.
 *
 *   npx tsx scripts/apply-researched-venue-fields.ts --dry-run
 *   npm run apply:researched
 */
const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SUPABASE_URL || !SERVICE_KEY) throw new Error("Missing Supabase env vars");

const DRY_RUN = process.argv.includes("--dry-run");
const HEADERS = {
  apikey: SERVICE_KEY,
  Authorization: `Bearer ${SERVICE_KEY}`,
  "Content-Type": "application/json",
};

interface Researched {
  /** Always the uuid. Names repeat across and within cities — 1702 W
   *  University Ave alone holds Rowdy's, Fats, Grove and Tela. */
  id: string;
  /** For the reader of this file only; the update never matches on it. */
  name: string;
  /** Column -> value to write. */
  fields: Record<string, unknown>;
  /** The page the value was read from, and when. */
  source: { url: string; fetched_at: string; notes?: string };
}

const RESEARCHED: Researched[] = [
  {
    id: "be6a6814-c1d0-4376-857d-3324e6d057b6",
    name: "Rowdy's — 1702 W University Ave, Midtown (was Rowdy Rudy's)",
    fields: { instagram_handle: "rowdys.gnv" },
    source: {
      url: "https://www.instagram.com/rowdys.gnv/",
      fetched_at: "2026-09-15",
      notes:
        "Live profile 'Rowdy's GNV', bio 'Some things never change', linktr.ee/rowdysgnv. " +
        "Handle cross-referenced from @lilrudysatmidtown.uf, the pre-rebrand account. " +
        "No hours published on the profile, the Linktree, Google or any website.",
    },
  },
  {
    id: "9b2975cb-8b10-49ec-b072-9da6ba2a7793",
    name: "Fats Gainesville — 1702 W University Ave, Midtown (was Lil' Rudy's)",
    fields: { instagram_handle: "fatsgnv" },
    source: {
      url: "https://www.instagram.com/fatsgnv/",
      fetched_at: "2026-09-15",
      notes:
        "Live profile 'Fats GNV', bio 'Your fave watering hole in Midtown', linktr.ee/fatsgnv. " +
        "Distinct business from Downtown Fats on S Main St, which closed 2026-05-01. " +
        "No hours published anywhere.",
    },
  },
  {
    id: "c181c556-4412-45e0-8c65-728d3b9b647c",
    name: "Signal Lounge — 7 SW 1st St, Downtown",
    fields: { instagram_handle: "signalgnv" },
    source: {
      url: "https://www.instagram.com/signalgnv/",
      fetched_at: "2026-09-15",
      notes:
        "Live profile 'Signal', bio \"Gainesville's space themed bar\", names @simons_gnv and " +
        "@theloftgnv as sister venues. Google has no hours for this place id.",
    },
  },
  {
    id: "cd4c7544-0ce0-40ce-a933-5e5045c4aeca",
    name: "Bourbon St Club & Bar — 116 SW 1st Ave, Downtown",
    fields: { instagram_handle: "bourbonstreetgnv" },
    source: {
      url: "https://www.instagram.com/bourbonstreetgnv/",
      fetched_at: "2026-09-15",
      notes:
        "Live profile 'Bourbon Street GNV', 2,024 followers, bio 'Let The Good Times Roll.' " +
        "Google has no hours, no website and no photo for this place id.",
    },
  },
];

async function main() {
  console.log(`${RESEARCHED.length} venues with hand-researched fields${DRY_RUN ? " (dry run)" : ""}\n`);
  let written = 0;

  for (const entry of RESEARCHED) {
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/venues?id=eq.${entry.id}&select=id,name,field_sources`,
      { headers: HEADERS },
    );
    if (!res.ok) { console.error(`  ${entry.name}: select ${res.status}`); continue; }
    const [row] = (await res.json()) as { id: string; name: string; field_sources: Record<string, unknown> | null }[];
    if (!row) { console.error(`  ${entry.name}: id not found — refusing to guess by name`); continue; }

    const sources: Record<string, unknown> = { ...(row.field_sources ?? {}) };
    for (const field of Object.keys(entry.fields)) {
      sources[field] = { source: "manual_research", method: "primary_source_read", ...entry.source };
    }

    const patch = { ...entry.fields, field_sources: sources };
    console.log(`  ${row.name} → ${Object.keys(entry.fields).join(", ")}  (${entry.source.url})`);
    if (DRY_RUN) { written++; continue; }

    const up = await fetch(`${SUPABASE_URL}/rest/v1/venues?id=eq.${entry.id}`, {
      method: "PATCH",
      headers: { ...HEADERS, Prefer: "return=minimal" },
      body: JSON.stringify(patch),
    });
    if (!up.ok) { console.error(`    ERROR ${up.status}: ${(await up.text()).slice(0, 120)}`); continue; }
    written++;
  }

  console.log(`\n${DRY_RUN ? "[DRY RUN] " : ""}venues written: ${written}/${RESEARCHED.length}`);
}

main().catch((e) => { console.error(e); process.exit(1); });

export {};
