import { defineConfig, devices } from "@playwright/test";
export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: process.env.CI ? 2 : 3,
  reporter: "list",
  use: { baseURL: "http://127.0.0.1:4173", trace: "off", screenshot: "off" },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: [
    {
      command:
        "npm run build:preview -- --outDir dist/fixtures && npm run preview -- --outDir dist/fixtures --port 4173",
      url: "http://127.0.0.1:4173",
      reuseExistingServer: false,
      timeout: 120000,
    },
    {
      command:
        "npm run build -- --outDir dist/closed && npm run preview -- --outDir dist/closed --port 4174",
      url: "http://127.0.0.1:4174",
      reuseExistingServer: false,
      timeout: 120000,
    },
  ],
});
