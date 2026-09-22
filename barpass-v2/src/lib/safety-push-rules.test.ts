import { describe, expect, it } from "vitest";
import {
  apnsHeaders,
  buildRefreshPayload,
  buildSeekLeaderPayload,
  cleanName,
  isDeadTokenReason,
  MAX_PAYLOAD_BYTES,
  payloadByteLength,
} from "./safety-push-rules";

const base = {
  seekId: "6f1c0b8e-6c1a-4d0e-9d55-0c3f6f1c0b8e",
  groupId: "a2b4c6d8-1111-4222-8333-444455556666",
  seekerName: "Juan",
  expiresAt: "2026-09-20T02:00:00Z",
};

describe("buildRefreshPayload — the silent push", () => {
  const payload = buildRefreshPayload(base.groupId) as { aps: Record<string, unknown> } & Record<string, unknown>;

  // If a silent push ever grows an alert or sound it stops being silent and
  // becomes an interruption nobody asked for — no other test would notice.
  it("has no alert, sound or badge", () => {
    expect(payload.aps).toEqual({ "content-available": 1 });
  });

  it("carries no location or personal data", () => {
    expect(Object.keys(payload).sort()).toEqual(["alert_type", "aps", "group_id"]);
    expect(JSON.stringify(payload)).not.toMatch(/lat|lng|lon|coord|location|name/i);
  });
});

describe("buildSeekLeaderPayload — state B, the alert to the leader", () => {
  const payload = buildSeekLeaderPayload(base) as {
    aps: { alert: { title: string; body: string }; category: string; "interruption-level": string };
  } & Record<string, unknown>;

  it("is a visible alert the app can route by alert_type", () => {
    expect(payload.alert_type).toBe("seek_leader");
    expect(payload.aps.category).toBe("SAFETY_SEEK_LEADER");
  });

  it("says exactly what the spec says", () => {
    expect(payload.aps.alert.body).toBe("Juan is looking for you. Open BarPass to connect radar.");
  });

  // The whole point of the pivot: it opens a RADAR after a tap, and breaks
  // through Focus so the leader actually sees it.
  it("is time-sensitive", () => {
    expect(payload.aps["interruption-level"]).toBe("time-sensitive");
  });

  it("carries the ids the phone verifies server-side before opening the radar", () => {
    expect(payload.seek_id).toBe(base.seekId);
    expect(payload.group_id).toBe(base.groupId);
    expect(payload.expires_at).toBe(base.expiresAt);
  });

  // There is no way to ask this payload to light a torch: nothing in it names
  // a beacon, a color, a rhythm or an ignition.
  it("cannot itself ask for the beacon", () => {
    expect(Object.keys(payload).sort()).toEqual(["alert_type", "aps", "expires_at", "group_id", "seek_id"]);
    expect(JSON.stringify(payload)).not.toMatch(/beacon|ignite|torch|flash|rhythm/i);
  });

  it("never carries a position, a distance or a direction", () => {
    expect(JSON.stringify(payload)).not.toMatch(
      /"lat"|"lng"|latitude|longitude|coordinates|location|distance|meters|azimuth|direction|heading/i,
    );
  });

  it("stays far under the APNs size limit even with a hostile name", () => {
    const big = buildSeekLeaderPayload({ ...base, seekerName: "x".repeat(10_000) });
    expect(payloadByteLength(big)).toBeLessThan(MAX_PAYLOAD_BYTES);
  });

  it("falls back to a generic line when the seeker has no name", () => {
    const anon = buildSeekLeaderPayload({ ...base, seekerName: null }) as typeof payload;
    expect(anon.aps.alert.body).toBe("Someone in your group is looking for you. Open BarPass to connect radar.");
  });
});

describe("cleanName", () => {
  it("strips control characters and collapses whitespace", () => {
    expect(cleanName("  Jo\u0000r\ndan \t X ")).toBe("Jo r dan X");
  });
  it("truncates long names with an ellipsis", () => {
    const out = cleanName("a".repeat(100));
    expect(out.length).toBe(40);
    expect(out.endsWith("…")).toBe(true);
  });
  it("returns empty for null/blank", () => {
    expect(cleanName(null)).toBe("");
    expect(cleanName("   ")).toBe("");
  });
});

describe("apnsHeaders", () => {
  it("sends alerts at priority 10 and background pushes at 5", () => {
    expect(apnsHeaders("alert", "com.x", 100)["apns-priority"]).toBe("10");
    expect(apnsHeaders("background", "com.x", 0)["apns-priority"]).toBe("5");
  });
  // Apple rejects a background push at priority 10.
  it("labels the push type so APNs accepts it", () => {
    expect(apnsHeaders("background", "com.x", 0)["apns-push-type"]).toBe("background");
    expect(apnsHeaders("alert", "com.x", 0)["apns-push-type"]).toBe("alert");
  });
  it("never sends a negative expiration", () => {
    expect(apnsHeaders("alert", "com.x", -5)["apns-expiration"]).toBe("0");
  });
});

describe("isDeadTokenReason", () => {
  it("treats 410 as dead", () => expect(isDeadTokenReason(410, undefined)).toBe(true));
  it("treats BadDeviceToken as dead", () => expect(isDeadTokenReason(400, "BadDeviceToken")).toBe(true));
  it("does not delete a token over a payload or auth problem", () => {
    expect(isDeadTokenReason(400, "BadTopic")).toBe(false);
    expect(isDeadTokenReason(403, "ExpiredProviderToken")).toBe(false);
    expect(isDeadTokenReason(429, "TooManyRequests")).toBe(false);
  });
});
