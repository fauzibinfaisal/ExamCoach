import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { expect, it } from "vitest";
import { App } from "./App";
import { previewReady } from "./data/link-repository";
import { parseLinkStatus, type LinkRepository } from "./domain/link-contract";

function show(repository: LinkRepository) {
  return render(
    <App
      route={{ page: "mock-test", preview: true, scenario: "ready" }}
      repository={repository}
    />,
  );
}
it("announces loading, then ready without enabling the exam", async () => {
  show({ readLanding: async () => parseLinkStatus(previewReady) });
  expect(screen.getByRole("status")).toHaveTextContent(
    "Memeriksa akses tryout",
  );
  await screen.findByRole("heading", { name: "Siapkan ruang fokus Anda." });
  expect(screen.getByRole("button", { name: "Mulai tryout" })).toBeDisabled();
  expect(screen.queryByRole("radio")).not.toBeInTheDocument();
});
it.each(["claimed", "expired", "revoked", "completed", "invalid"])(
  "never exposes questions/metadata/start on %s",
  async (status) => {
    show({
      readLanding: async () => parseLinkStatus({ schemaVersion: 1, status }),
    });
    await screen.findByRole("link", { name: /Kembali ke profil utama/ });
    expect(
      screen.queryByText(previewReady.tryout.title),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: "Mulai tryout" }),
    ).not.toBeInTheDocument();
    expect(screen.queryByRole("radio")).not.toBeInTheDocument();
  },
);
it("does not echo repository failures", async () => {
  show({
    readLanding: async () => {
      throw new Error("canary-private-token");
    },
  });
  await screen.findByRole("heading", { name: "Akses tryout belum tersedia" });
  expect(document.body.textContent).not.toContain("canary-private-token");
});
it("ignores a response after unmount", async () => {
  let resolve!: (value: ReturnType<typeof parseLinkStatus>) => void;
  let signal: AbortSignal | undefined;
  const view = show({
    readLanding: (s) => {
      signal = s;
      return new Promise((r) => {
        resolve = r;
      });
    },
  });
  view.unmount();
  expect(signal?.aborted).toBe(true);
  resolve(parseLinkStatus(previewReady));
  await waitFor(() =>
    expect(
      screen.queryByText(previewReady.tryout.title),
    ).not.toBeInTheDocument(),
  );
});
it("supports keyboard focus through skip link and navigation", async () => {
  const user = userEvent.setup();
  show({ readLanding: async () => ({ schemaVersion: 1, status: "expired" }) });
  await user.tab();
  expect(
    screen.getByRole("link", { name: "Lewati ke konten utama" }),
  ).toHaveFocus();
  await user.tab();
  expect(
    screen.getByRole("link", { name: "ExamCoach, profil utama" }),
  ).toHaveFocus();
  await user.tab();
  expect(
    within(screen.getByRole("navigation")).getByRole("link", {
      name: "Profil utama",
    }),
  ).toHaveFocus();
});
