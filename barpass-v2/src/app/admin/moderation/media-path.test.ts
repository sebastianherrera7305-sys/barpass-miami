import { describe, expect, it } from "vitest";
import { storagePathFromPublicUrl } from "./media-path";

const BASE = "https://example.supabase.co/storage/v1";

describe("storagePathFromPublicUrl", () => {
  it("reads the key out of a public object URL", () => {
    expect(storagePathFromPublicUrl(`${BASE}/object/public/venue-media/abc-123/img.jpg`)).toBe(
      "abc-123/img.jpg",
    );
  });

  it("handles signed and authenticated URLs, ignoring the query string", () => {
    expect(
      storagePathFromPublicUrl(`${BASE}/object/sign/venue-media/abc/img.jpg?token=xyz`),
    ).toBe("abc/img.jpg");
    expect(storagePathFromPublicUrl(`${BASE}/object/authenticated/venue-media/abc/v.mp4`)).toBe(
      "abc/v.mp4",
    );
  });

  it("decodes percent-encoding, because Storage keys are stored decoded", () => {
    expect(
      storagePathFromPublicUrl(`${BASE}/object/public/venue-media/abc/night%20out.jpg`),
    ).toBe("abc/night out.jpg");
  });

  it("returns null for another bucket, so we never delete someone else's file", () => {
    expect(storagePathFromPublicUrl(`${BASE}/object/public/avatars/abc/img.jpg`)).toBeNull();
  });

  it("returns null for anything that isn't a Storage URL", () => {
    expect(storagePathFromPublicUrl("https://cdn.example.com/a.jpg")).toBeNull();
    expect(storagePathFromPublicUrl("not a url")).toBeNull();
    expect(storagePathFromPublicUrl("")).toBeNull();
  });

  it("refuses traversal segments", () => {
    expect(storagePathFromPublicUrl(`${BASE}/object/public/venue-media/abc/../other/x.jpg`)).toBeNull();
    expect(storagePathFromPublicUrl(`${BASE}/object/public/venue-media/abc/%2E%2E/x.jpg`)).toBeNull();
  });
});
