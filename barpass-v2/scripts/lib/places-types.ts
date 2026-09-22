/**
 * The shapes the Places meter and its callers agree on, plus the one number
 * that decides how big a run is allowed to get.
 *
 * Kept apart from the meter so that a script, a test, or a future planner can
 * name a result or a cap without importing the machinery that spends money.
 */

export interface MinimalResponse {
  ok: boolean;
  status: number;
  json(): Promise<unknown>;
  text(): Promise<string>;
}
export interface FetchInit { method?: string; headers?: Record<string, string>; body?: string }
export type FetchLike = (url: string, init?: FetchInit) => Promise<MinimalResponse>;

/**
 * The catalogue is 4,417 venues, so one honest whole-catalogue pass is 4,417
 * calls. 5,000 is the next round number above that: a full sweep fits in one
 * run with ~13% headroom for retries, while the failure we actually fear — a
 * loop that re-queues venues, or a retry storm — trips the cap before it can
 * double the bill. Raise it per run, deliberately, never as a default.
 */
export const DEFAULT_MAX_CALLS = 5000;

export type PlacesResult<T> =
  | { status: "ok"; data: T; cached: boolean }
  | { status: "dryRun"; cached: boolean }
  | { status: "capped" }
  | { status: "failed"; httpStatus: number; body: string };

export interface PlacesClientOptions {
  apiKey?: string;
  /**
   * Spending is OPT-IN; the default is a dry run — deliberately the opposite of
   * how the sweep scripts behaved on 2026-09-14. The asymmetry is the argument:
   * a wrong "spend" default costs real money silently and cannot be undone, a
   * wrong "dry run" default costs one re-run with a flag. Only one of the two
   * reaches a card statement. Set spend:true, or PLACES_SPEND=1, and mean it.
   */
  spend?: boolean;
  maxCalls?: number;
  /** Injected in tests so a dry run can be PROVEN not to touch the network. */
  fetchImpl?: FetchLike;
  /** Shows up in the report, so a stray run can be traced to its script. */
  label?: string;
  log?: (line: string) => void;
  /** Off in tests; on for real scripts, where the exit report is the point. */
  reportOnExit?: boolean;
}
