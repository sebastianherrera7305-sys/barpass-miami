/**
 * The one door. Every script that needs Google Places goes through this class,
 * and `places-calls.ts` is the thin retry/unwrap layer the sweeps sit on.
 *
 * On 2026-09-14 eleven scripts each held their own `fetch` to the Places API.
 * No single place knew how many calls a run would make or what they would cost,
 * so a 2,510-venue sweep became a USD 655 line on the founder's card with no
 * warning anywhere in between. This module is the one door, and it is shut by
 * default.
 *
 * Guarantees: it prices a request before issuing it; it spends nothing unless
 * spending was asked for explicitly; it stops at a hard call cap and says how
 * many it refused; it prints what it spent even when the script dies on an
 * exception; and it fetches a given place once per run, however many callers
 * ask for it.
 *
 * Numbers printed are ESTIMATES from list prices. Read the banner in
 * places-pricing.ts before quoting one at anybody.
 */

import {
  costOfRequest,
  formatUsd,
  PRICING_READ_ON,
  PRICING_SOURCE,
  usdFor,
  type BilledTier,
  type PlacesEndpoint,
} from "./places-pricing";
import {
  DEFAULT_MAX_CALLS,
  type FetchLike,
  type FetchInit,
  type PlacesClientOptions,
  type PlacesResult,
} from "./places-types";

export * from "./places-types";
export {
  costOfRequest,
  estimateSweep,
  formatUsd,
  tierOfField,
  usdFor,
  PRICING_READ_ON,
  PRICING_SOURCE,
  USD_PER_1000,
  type BilledTier,
  type PlacesEndpoint,
  type SkuTier,
} from "./places-pricing";

interface Tally { calls: number; usd: number }
interface CacheEntry { fields: Set<string>; data: unknown }

export class PlacesClient {
  private readonly apiKey: string;
  private readonly spend: boolean;
  private readonly maxCalls: number;
  private readonly doFetch: FetchLike;
  private readonly label: string;
  private readonly log: (line: string) => void;

  private readonly tallies = new Map<string, Tally>();
  private readonly cache = new Map<string, CacheEntry>();
  private readonly unknownFields = new Set<string>();

  private callsIssued = 0;
  private cacheHits = 0;
  private cappedCalls = 0;
  /** Places fetched more than once because a later mask wanted more fields.
   *  This count IS the 2026-09-14 bug, measured. Non-zero means: merge masks. */
  private remasked = 0;
  private reported = false;

  constructor(opts: PlacesClientOptions = {}) {
    this.apiKey = opts.apiKey ?? process.env.GOOGLE_PLACES_API_KEY ?? "";
    this.spend = opts.spend ?? process.env.PLACES_SPEND === "1";
    this.maxCalls = opts.maxCalls ?? numberFromEnv("PLACES_MAX_CALLS") ?? DEFAULT_MAX_CALLS;
    this.doFetch = opts.fetchImpl ?? (fetch as FetchLike);
    this.label = opts.label ?? "places";
    this.log = opts.log ?? ((line) => console.log(line));
    if (opts.reportOnExit ?? true) this.installExitReport();
  }

  get isDryRun(): boolean {
    return !this.spend;
  }

  /** Place Details for one venue. `mask` is the X-Goog-FieldMask, verbatim. */
  async placeDetails<T>(placeId: string, mask: string | readonly string[]): Promise<PlacesResult<T>> {
    const fieldMask = toMask(mask);
    return this.request<T>({
      endpoint: "details",
      cacheKey: `details:${placeId}`,
      mask: fieldMask,
      url: `https://places.googleapis.com/v1/places/${placeId}`,
      init: { headers: { "X-Goog-Api-Key": this.apiKey, "X-Goog-FieldMask": fieldMask } },
    });
  }

  /** Text Search — its own, dearer, SKU ladder. Price it before sweeping. */
  async searchText<T>(q: string, mask: string | readonly string[]): Promise<PlacesResult<T>> {
    return this.search<T>("textSearch", "searchText", { textQuery: q }, mask);
  }

  /** Nearby Search — same ladder as Text Search, same warning. */
  async searchNearby<T>(
    body: Record<string, unknown>,
    mask: string | readonly string[],
  ): Promise<PlacesResult<T>> {
    return this.search<T>("nearbySearch", "searchNearby", body, mask);
  }

  private async search<T>(
    endpoint: PlacesEndpoint,
    method: string,
    body: Record<string, unknown>,
    mask: string | readonly string[],
  ): Promise<PlacesResult<T>> {
    const fieldMask = toMask(mask);
    return this.request<T>({
      endpoint,
      cacheKey: `${method}:${JSON.stringify(body)}`,
      mask: fieldMask,
      url: `https://places.googleapis.com/v1/places:${method}`,
      init: {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Goog-Api-Key": this.apiKey,
          "X-Goog-FieldMask": fieldMask,
        },
        body: JSON.stringify(body),
      },
    });
  }

  /** Photo bytes. Flat SKU, no field mask, and it is NOT free. */
  async photo<T>(photoName: string, query = "maxWidthPx=1200&skipHttpRedirect=true"): Promise<PlacesResult<T>> {
    return this.request<T>({
      endpoint: "photo",
      cacheKey: `photo:${photoName}:${query}`,
      mask: "",
      url: `https://places.googleapis.com/v1/${photoName}/media?${query}`,
      init: { headers: { "X-Goog-Api-Key": this.apiKey } },
    });
  }

  private async request<T>(spec: {
    endpoint: PlacesEndpoint;
    cacheKey: string;
    mask: string;
    url: string;
    init: FetchInit;
  }): Promise<PlacesResult<T>> {
    const cost = costOfRequest(spec.endpoint, spec.mask);
    for (const f of cost.unknownFields) this.unknownFields.add(f);

    // Per-run cache. A hit only counts if the earlier call asked for AT LEAST
    // the fields this one wants — otherwise we would hand back a response with
    // the field the caller came for missing, which is worse than paying again.
    const wanted = new Set(splitMask(spec.mask));
    const hit = this.cache.get(spec.cacheKey);
    if (hit && [...wanted].every((f) => hit.fields.has(f))) {
      this.cacheHits++;
      return this.isDryRun
        ? { status: "dryRun", cached: true }
        : { status: "ok", data: hit.data as T, cached: true };
    }
    if (hit) this.remasked++;

    if (this.callsIssued >= this.maxCalls) {
      this.cappedCalls++;
      return { status: "capped" };
    }

    // Counted BEFORE the await: a call that throws mid-flight may still have
    // been billed, and an estimate that under-reports is the failure mode here.
    this.callsIssued++;
    this.record(spec.endpoint, cost.tier, cost.usd);

    // The dry run stops HERE, before the network, by construction rather than
    // by a flag checked inside the fetch. Nothing below runs.
    if (this.isDryRun) {
      this.cache.set(spec.cacheKey, { fields: wanted, data: undefined });
      return { status: "dryRun", cached: false };
    }

    const res = await this.doFetch(spec.url, spec.init);
    if (!res.ok) {
      return { status: "failed", httpStatus: res.status, body: await res.text() };
    }
    const data = (await res.json()) as T;
    this.cache.set(spec.cacheKey, { fields: wanted, data });
    return { status: "ok", data, cached: false };
  }

  private record(endpoint: PlacesEndpoint, tier: BilledTier, usd: number): void {
    const key = `${endpoint}/${tier}`;
    const tally = this.tallies.get(key) ?? { calls: 0, usd: 0 };
    tally.calls++;
    tally.usd += usd;
    this.tallies.set(key, tally);
  }

  get estimatedUsd(): number {
    return [...this.tallies.values()].reduce((sum, t) => sum + t.usd, 0);
  }

  get stats() {
    return {
      callsIssued: this.callsIssued,
      cacheHits: this.cacheHits,
      cappedCalls: this.cappedCalls,
      remasked: this.remasked,
      estimatedUsd: this.estimatedUsd,
      dryRun: this.isDryRun,
    };
  }

  report(): string {
    const mode = this.isDryRun
      ? "DRY RUN — no network call was made, nothing was spent"
      : "LIVE — real money";
    const lines = [
      `--- Places meter: ${this.label} ---`,
      `mode: ${mode}`,
      `calls: ${this.callsIssued}  ·  served from cache: ${this.cacheHits}  ·  refused by cap: ${this.cappedCalls}`,
    ];
    for (const [key, t] of [...this.tallies.entries()].sort()) {
      lines.push(`  ${key.padEnd(26)} ${String(t.calls).padStart(6)} calls   ${formatUsd(t.usd)}`);
    }
    lines.push(
      `${this.isDryRun ? "estimated if run" : "estimated spend"}: ${formatUsd(this.estimatedUsd)}`,
      `  (list prices read ${PRICING_READ_ON} — an estimate, not an invoice: ${PRICING_SOURCE})`,
    );
    if (this.cappedCalls > 0) {
      lines.push(
        `cap of ${this.maxCalls} hit: ${this.cappedCalls} call(s) were refused and their venues left untouched.`,
        `  Re-run for the rest, or raise maxCalls once you have read the estimate above.`,
      );
    }
    if (this.remasked > 0) {
      lines.push(
        `${this.remasked} place(s) were fetched again for a wider field mask — this is the`,
        `  2026-09-14 bug in miniature. Merge those masks into one call.`,
      );
    }
    if (this.unknownFields.size > 0) {
      lines.push(
        `unrecognised field(s), billed at the dearest tier to be safe: ${[...this.unknownFields].join(", ")}`,
      );
    }
    return lines.join("\n");
  }

  /** Idempotent: the exit hook and an explicit call must not double-print. */
  printReport(): void {
    if (this.reported) return;
    this.reported = true;
    this.log(this.report());
  }

  /**
   * The report has to survive the bad path, not just the happy one. 'exit' runs
   * after an uncaught exception too, which is exactly when you most want to know
   * what the run already spent before it died.
   */
  private installExitReport(): void {
    process.on("exit", () => this.printReport());
    process.on("SIGINT", () => {
      this.printReport();
      process.exit(130);
    });
  }
}

function toMask(mask: string | readonly string[]): string {
  return Array.isArray(mask) ? mask.join(",") : (mask as string);
}

function splitMask(mask: string): string[] {
  return mask.split(",").map((f) => f.trim()).filter((f) => f.length > 0);
}

function numberFromEnv(name: string): number | undefined {
  const raw = process.env[name];
  if (!raw) return undefined;
  const n = Number.parseInt(raw, 10);
  return Number.isFinite(n) && n > 0 ? n : undefined;
}
