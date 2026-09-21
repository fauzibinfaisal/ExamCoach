import { expect, it, vi } from "vitest";
import {
  FakeLinkRepository,
  UnavailableLinkRepository,
} from "./link-repository";
import { linkStates } from "../domain/link-contract";

it.each(linkStates.filter((value) => value !== "validating"))(
  "returns explicit %s fixture",
  async (status) => {
    vi.useFakeTimers();
    try {
      const pending = new FakeLinkRepository(status).readLanding(
        new AbortController().signal,
      );
      await vi.runAllTimersAsync();
      expect((await pending).status).toBe(status);
    } finally {
      vi.useRealTimers();
    }
  },
);
it("cancels a pending loading fixture and already-aborted requests", async () => {
  const controller = new AbortController();
  const repository = new FakeLinkRepository("validating");
  const pending = expect(
    repository.readLanding(controller.signal),
  ).rejects.toMatchObject({ name: "AbortError" });
  controller.abort();
  await pending;
  await expect(repository.readLanding(controller.signal)).rejects.toMatchObject(
    { name: "AbortError" },
  );
});
it("default adapter cannot grant access", async () => {
  expect(await new UnavailableLinkRepository().readLanding()).toEqual({
    schemaVersion: 1,
    status: "invalid",
  });
});
