import { describe, expect, it } from "vitest";
import Ajv2020 from "ajv/dist/2020";
import schema from "../../../../contracts/web-cbt/link-status.v1.schema.json";
import { linkContractJsonSchema, parseLinkStatus } from "./link-contract";
import { previewReady } from "../data/link-repository";

describe("public landing contract", () => {
  it("keeps the language-neutral schema aligned with the runtime parser", () => {
    expect(schema).toEqual(linkContractJsonSchema);
    const validate = new Ajv2020().compile(schema);
    expect(validate(previewReady)).toBe(true);
    expect(
      validate({
        schemaVersion: 1,
        status: "expired",
        tryout: previewReady.tryout,
      }),
    ).toBe(false);
  });
  it.each(["claimed", "expired", "revoked", "completed", "invalid"])(
    "redacts %s metadata",
    (status) => {
      expect(parseLinkStatus({ schemaVersion: 1, status })).toEqual({
        schemaVersion: 1,
        status,
      });
      expect(() =>
        parseLinkStatus({
          schemaVersion: 1,
          status,
          tryout: previewReady.tryout,
        }),
      ).toThrow("Invalid link status response");
    },
  );
  it("accepts ready metadata and uses server timestamps without client Date", () => {
    expect(parseLinkStatus(previewReady)).toEqual(previewReady);
  });
  it.each([
    null,
    {},
    { schemaVersion: 2, status: "ready" },
    { schemaVersion: 1, status: "validating" },
    { ...previewReady, token: "canary-do-not-echo" },
    { ...previewReady, ownerUid: "owner" },
  ])("rejects unknown or private response shape %#", (input) => {
    expect(() => parseLinkStatus(input)).toThrow(
      /^Invalid link status response$/,
    );
  });
  it("rejects invalid clocks and a lifetime other than the server contract", () => {
    expect(() =>
      parseLinkStatus({
        ...previewReady,
        serverNowMs: previewReady.createdAtMs - 1,
      }),
    ).toThrow();
    expect(() =>
      parseLinkStatus({
        ...previewReady,
        expiresAtMs: previewReady.expiresAtMs + 1,
      }),
    ).toThrow();
    expect(() =>
      parseLinkStatus({ ...previewReady, serverNowMs: NaN }),
    ).toThrow();
  });
  it("closes an expired or too-short ready response without retaining metadata", () => {
    expect(
      parseLinkStatus({
        ...previewReady,
        serverNowMs: previewReady.expiresAtMs,
      }),
    ).toEqual({ schemaVersion: 1, status: "expired" });
    expect(
      parseLinkStatus({
        ...previewReady,
        serverNowMs: previewReady.expiresAtMs - 2_459_999,
      }),
    ).toEqual({ schemaVersion: 1, status: "invalid" });
    expect(
      parseLinkStatus({
        ...previewReady,
        serverNowMs: previewReady.expiresAtMs - 2_460_000,
      }).status,
    ).toBe("ready");
  });
});
