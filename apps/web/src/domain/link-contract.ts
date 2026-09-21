import { z } from "zod";

export const linkStates = [
  "validating",
  "ready",
  "claimed",
  "expired",
  "revoked",
  "completed",
  "invalid",
] as const;
export type LinkState = (typeof linkStates)[number];
const timestamp = z.number().int().min(0).max(8_640_000_000_000_000);
const denied = [
  "claimed",
  "expired",
  "revoked",
  "completed",
  "invalid",
] as const;

// Public landing data only. No owner, internal IDs, question content or credentials.
export const linkEnvelopeSchema = z.discriminatedUnion("status", [
  z
    .object({
      schemaVersion: z.literal(1),
      status: z.literal("ready"),
      serverNowMs: timestamp,
      createdAtMs: timestamp,
      expiresAtMs: timestamp,
      tryout: z
        .object({
          title: z.string().trim().min(1).max(120),
          subtests: z.array(z.string().trim().min(1).max(60)).min(1).max(10),
          questionCount: z.number().int().min(1).max(500),
          durationSeconds: z.number().int().min(1).max(43_200),
          submissionGraceSeconds: z.number().int().min(0).max(600),
        })
        .strict(),
    })
    .strict(),
  ...denied.map((status) =>
    z
      .object({
        schemaVersion: z.literal(1),
        status: z.literal(status),
      })
      .strict(),
  ),
]);
export type LinkStatus = z.infer<typeof linkEnvelopeSchema>;
export type LandingState = LinkStatus | { status: "validating" };
export const invalidLink: LinkStatus = { schemaVersion: 1, status: "invalid" };
export const linkContractJsonSchema = {
  ...z.toJSONSchema(linkEnvelopeSchema),
  $id: "urn:examcoach:web-cbt:link-status:v1",
};

export function parseLinkStatus(input: unknown): LinkStatus {
  const parsed = linkEnvelopeSchema.safeParse(input);
  // Never propagate parser diagnostics: an untrusted response may contain secrets.
  if (!parsed.success) throw new Error("Invalid link status response");
  const value = parsed.data;
  if (value.status !== "ready") return value;
  if (
    value.createdAtMs > value.serverNowMs ||
    value.expiresAtMs - value.createdAtMs !== 43_200_000
  ) {
    throw new Error("Invalid link status response");
  }
  const remaining = value.expiresAtMs - value.serverNowMs;
  if (remaining <= 0) return { schemaVersion: 1, status: "expired" };
  if (
    remaining <
    (value.tryout.durationSeconds + value.tryout.submissionGraceSeconds) * 1000
  ) {
    return invalidLink;
  }
  return value;
}

export interface LinkRepository {
  readLanding(signal: AbortSignal): Promise<LinkStatus>;
}
