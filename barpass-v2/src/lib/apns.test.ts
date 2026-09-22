import { generateKeyPairSync, createVerify } from "node:crypto";
import { describe, expect, it } from "vitest";
import { apnsConfig, providerToken } from "./apns";

const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
const pem = privateKey.export({ type: "pkcs8", format: "pem" }).toString();

const config = { keyId: "ABC123DEFG", teamId: "TEAM123456", privateKeyPem: pem, bundleId: "com.sebastian.barpass" };

describe("apnsConfig", () => {
  it("is null unless key id, team id and key are all present", () => {
    expect(apnsConfig({})).toBeNull();
    expect(apnsConfig({ APNS_KEY_ID: "a", APNS_TEAM_ID: "b" })).toBeNull();
  });
  it("accepts a key whose newlines were flattened to \\n", () => {
    const flat = pem.replace(/\n/g, "\\n");
    const cfg = apnsConfig({ APNS_KEY_ID: "a", APNS_TEAM_ID: "b", APNS_PRIVATE_KEY: flat });
    expect(cfg?.privateKeyPem).toBe(pem);
    expect(cfg?.bundleId).toBe("com.sebastian.barpass");
  });
});

describe("providerToken", () => {
  it("is an ES256 JWT Apple can verify: right header, claims and raw r||s signature", () => {
    const now = 1_800_000_000;
    const [h, c, s] = providerToken({ ...config, keyId: "KEY-A" }, now).split(".");
    expect(JSON.parse(Buffer.from(h, "base64url").toString())).toEqual({ alg: "ES256", kid: "KEY-A" });
    expect(JSON.parse(Buffer.from(c, "base64url").toString())).toEqual({ iss: "TEAM123456", iat: now });

    const verifier = createVerify("SHA256");
    verifier.update(`${h}.${c}`);
    expect(verifier.verify({ key: publicKey, dsaEncoding: "ieee-p1363" }, Buffer.from(s, "base64url"))).toBe(true);
    // Raw ES256 is exactly 64 bytes; a DER signature would not be.
    expect(Buffer.from(s, "base64url").length).toBe(64);
  });

  it("reuses the token inside its window and mints a new one after", () => {
    const first = providerToken({ ...config, keyId: "KEY-B" }, 1_800_000_000);
    expect(providerToken({ ...config, keyId: "KEY-B" }, 1_800_000_000 + 600)).toBe(first);
    expect(providerToken({ ...config, keyId: "KEY-B" }, 1_800_000_000 + 60 * 60)).not.toBe(first);
  });
});
