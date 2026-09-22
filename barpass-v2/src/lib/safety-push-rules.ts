/**
 * Pure payload rules for the safety-group pushes. No network, no env — so
 * they are unit-testable and the one place that decides what a push may
 * contain.
 *
 * Three invariants, all enforced here and tested:
 *
 *  1. A "silent" push carries NO alert, NO sound and NO data beyond
 *     "refresh". It never carries a location: this feature does not put
 *     anyone's coordinates on the server (see supabase/safety_groups.sql).
 *  2. The seek push is a visible, time-sensitive alert that goes ONLY to the
 *     group leader (the RPC that picks recipients returns nobody else). It
 *     lights nothing by arriving: it opens the radar after a tap, and the
 *     rally point needs a SECOND tap on the leader's own phone (BarPass-iOS
 *     SafetyPushRouter).
 *  3. No payload ever carries a position, a distance or a direction.
 */

export type ApnsEnvironment = "sandbox" | "production";

export interface PushTarget {
  token: string;
  environment: ApnsEnvironment;
}

export interface SeekLeaderPayloadInput {
  seekId: string;
  groupId: string;
  seekerName: string | null;
  expiresAt: string;
}

/** APNs rejects a payload over 4096 bytes; alerts here are a few hundred. */
export const MAX_PAYLOAD_BYTES = 4096;

const NAME_MAX = 40;

/** Untrusted display name → something safe to put in a notification line. */
export function cleanName(raw: string | null | undefined): string {
  const collapsed = (raw ?? "").replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim();
  if (!collapsed) return "";
  return collapsed.length > NAME_MAX ? `${collapsed.slice(0, NAME_MAX - 1)}…` : collapsed;
}

/**
 * STATE B of the handshake: the seeker tapped "Find Leader" and the leader is
 * told to open BarPass so the two phones can start ranging.
 *
 * `time-sensitive` needs the app's own entitlement
 * (com.apple.developer.usernotifications.time-sensitive, added to
 * BarPass.entitlements together with the Time Sensitive Notifications
 * capability). Without it iOS quietly delivers a normal notification, so the
 * feature still works, just without breaking through a Focus.
 *
 * The text is English, as specified: the server does not know the recipient's
 * language (the app's strings are an in-code dictionary, so there is no
 * Localizable.strings for `loc-key` to point at).
 */
export function buildSeekLeaderPayload(input: SeekLeaderPayloadInput): Record<string, unknown> {
  const name = cleanName(input.seekerName);
  const who = name || "Someone in your group";
  return {
    aps: {
      alert: {
        title: "BarPass",
        body: `${who} is looking for you. Open BarPass to connect radar.`,
      },
      sound: "default",
      "interruption-level": "time-sensitive",
      category: "SAFETY_SEEK_LEADER",
      "thread-id": input.groupId,
    },
    alert_type: "seek_leader",
    seek_id: input.seekId,
    group_id: input.groupId,
    expires_at: input.expiresAt,
  };
}

/** Silent "something changed, refresh". No alert, no sound, no data. */
export function buildRefreshPayload(groupId: string): Record<string, unknown> {
  return {
    aps: { "content-available": 1 },
    alert_type: "group_refresh",
    group_id: groupId,
  };
}

export function payloadByteLength(payload: Record<string, unknown>): number {
  return Buffer.byteLength(JSON.stringify(payload), "utf8");
}

export type PushKind = "alert" | "background";

/** Headers APNs needs per kind. Background pushes are low priority by rule. */
export function apnsHeaders(kind: PushKind, topic: string, expiresAtUnix: number): Record<string, string> {
  return {
    "apns-topic": topic,
    "apns-push-type": kind,
    "apns-priority": kind === "alert" ? "10" : "5",
    "apns-expiration": String(Math.max(0, Math.floor(expiresAtUnix))),
  };
}

/** APNs reasons that mean the token is permanently dead and should be deleted. */
export function isDeadTokenReason(status: number, reason: string | undefined): boolean {
  if (status === 410) return true;
  return status === 400 && (reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic");
}
