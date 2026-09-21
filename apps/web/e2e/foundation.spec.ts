import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

const states = {
  validating: "Memeriksa akses tryout",
  ready: "Siapkan ruang fokus Anda.",
  claimed: "Link terikat ke browser lain",
  expired: "Masa berlaku link telah berakhir",
  revoked: "Akses link telah dicabut",
  completed: "Sesi tryout telah selesai",
  invalid: "Akses tryout belum tersedia",
};
for (const [state, heading] of Object.entries(states)) {
  test(`${state}: public state, redaction and accessibility`, async ({
    page,
  }) => {
    await page.goto(`/mock-test?preview=${state}`);
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(heading);
    await expect(page).toHaveURL("/mock-test");
    await expect(page.getByRole("radio")).toHaveCount(0);
    if (state !== "ready") {
      await expect(
        page.getByRole("button", { name: "Mulai tryout" }),
      ).toHaveCount(0);
      await expect(
        page.getByText("Simulasi TIU · Penalaran dasar"),
      ).toHaveCount(0);
    } else {
      await expect(
        page.getByRole("button", { name: "Mulai tryout" }),
      ).toBeDisabled();
    }
    expect((await new AxeBuilder({ page }).analyze()).violations).toEqual([]);
  });
}
for (const width of [1440, 1280, 1024, 768, 375]) {
  test(`profile and ready reflow at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 1000 });
    for (const path of ["/profile", "/mock-test?preview=ready"]) {
      await page.goto(path);
      await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
      if (path.includes("mock-test"))
        await expect(
          page.getByText("Simulasi TIU · Penalaran dasar"),
        ).toBeVisible();
      expect(
        await page.evaluate(
          () => document.documentElement.scrollWidth <= window.innerWidth,
        ),
      ).toBe(true);
    }
  });
}
test("keyboard-only profile to landing, then terminal status", async ({
  page,
}) => {
  await page.goto("/profile");
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  await page.keyboard.press("Tab");
  await expect(
    page.getByRole("link", { name: "Lewati ke konten utama" }),
  ).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page.locator("main")).toBeFocused();
  await page.keyboard.press("Tab");
  await expect(
    page.getByRole("link", { name: /Lihat pratinjau tryout/ }),
  ).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page.getByRole("heading", { level: 1 })).toHaveText(
    states.ready,
  );
  await page.getByRole("link", { name: "expired", exact: true }).focus();
  await page.keyboard.press("Enter");
  await expect(page.getByRole("heading", { level: 1 })).toHaveText(
    states.expired,
  );
  await page.reload();
  await expect(page.getByRole("heading", { level: 1 })).toHaveText(
    states.invalid,
  );
});
test("default build refuses fixture input and unsafe paths", async ({
  page,
}) => {
  await page.goto("http://127.0.0.1:4174/mock-test?preview=ready");
  await expect(page.getByRole("heading", { level: 1 })).toHaveText(
    states.invalid,
  );
  await expect(page.getByRole("complementary")).toHaveCount(0);
  await page.goto("http://127.0.0.1:4174/mock-test/questions");
  await expect(page.getByRole("heading", { level: 1 })).toHaveText(
    "Halaman tidak ditemukan",
  );
  await expect(page.getByRole("radio")).toHaveCount(0);
});
test("fragment is discarded without storage, telemetry or network disclosure", async ({
  page,
  context,
}) => {
  const requested: string[] = [];
  const logs: string[] = [];
  page.on("request", (r) =>
    requested.push(r.url(), r.postData() ?? "", JSON.stringify(r.headers())),
  );
  page.on("console", (m) => logs.push(m.text()));
  page.on("pageerror", (e) => logs.push(e.message));
  await page.goto("/mock-test#synthetic-canary-never-a-real-token");
  await expect(page.getByRole("heading", { level: 1 })).toHaveText(
    states.invalid,
  );
  await expect(page).toHaveURL("/mock-test");
  expect(requested.join(" ")).not.toContain("synthetic-canary");
  expect(logs.join(" ")).not.toContain("synthetic-canary");
  expect(
    await page.evaluate(() => [localStorage.length, sessionStorage.length]),
  ).toEqual([0, 0]);
  expect(await context.cookies()).toEqual([]);
  expect(
    await page.evaluate(async () => (await indexedDB.databases()).length),
  ).toBe(0);
  expect(
    await page.evaluate(
      async () => (await navigator.serviceWorker.getRegistrations()).length,
    ),
  ).toBe(0);
});
test("profile is explicit sample context, accessible at 200% text", async ({
  page,
}) => {
  await page.goto("/profile");
  await expect(page.getByText("Belum masuk ke akun web")).toBeVisible();
  expect((await new AxeBuilder({ page }).analyze()).violations).toEqual([]);
  await page.setViewportSize({ width: 1024, height: 900 });
  await page.addStyleTag({ content: "html { font-size: 200%; }" });
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBe(true);
});
