import {
  invalidLink,
  parseLinkStatus,
  type LinkRepository,
  type LinkState,
  type LinkStatus,
} from "../domain/link-contract";

export const previewReady = {
  schemaVersion: 1,
  status: "ready",
  createdAtMs: 1_790_006_400_000,
  serverNowMs: 1_790_013_600_000,
  expiresAtMs: 1_790_049_600_000,
  tryout: {
    title: "Simulasi TIU · Penalaran dasar",
    subtests: ["Verbal", "Numerik", "Figural"],
    questionCount: 30,
    durationSeconds: 2400,
    submissionGraceSeconds: 60,
  },
} as const;

export class UnavailableLinkRepository implements LinkRepository {
  async readLanding(): Promise<LinkStatus> {
    return invalidLink;
  }
}

// Labels select UI fixtures. They are NEVER bearer tokens or proof of ownership.
// This repository has no claim, question, answer, submit or persistence API.
export class FakeLinkRepository implements LinkRepository {
  constructor(private readonly scenario: LinkState) {}
  readLanding(signal: AbortSignal): Promise<LinkStatus> {
    return new Promise((resolve, reject) => {
      if (signal.aborted) {
        reject(new DOMException("Aborted", "AbortError"));
        return;
      }
      const abort = () => {
        clearTimeout(timer);
        reject(new DOMException("Aborted", "AbortError"));
      };
      // A deliberately pending fixture allows keyboard/assistive loading-state QA.
      const timer =
        this.scenario === "validating"
          ? undefined
          : setTimeout(() => {
              signal.removeEventListener("abort", abort);
              resolve(
                parseLinkStatus(
                  this.scenario === "ready"
                    ? previewReady
                    : {
                        schemaVersion: 1,
                        status: this.scenario,
                      },
                ),
              );
            }, 250);
      signal.addEventListener("abort", abort, { once: true });
    });
  }
}
