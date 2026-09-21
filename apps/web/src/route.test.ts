import { expect, it, vi } from "vitest";
import { isPreviewAllowed, readRoute } from "./route";

it.each(["localhost", "127.0.0.1", "[::1]"])(
  "requires opt-in even on %s",
  (hostname) => {
    expect(isPreviewAllowed(false, hostname)).toBe(false);
    expect(isPreviewAllowed(true, hostname)).toBe(true);
  },
);
it.each(["examcoach.example", "127.0.0.1.evil.example", "192.168.0.1"])(
  "refuses fixtures on %s",
  (hostname) => expect(isPreviewAllowed(true, hostname)).toBe(false),
);
it.each([
  "?preview=ready&token=canary",
  "?token=canary",
  "?preview=unknown",
  "?preview=ready&preview=expired",
])("discards unsafe fixture input %s", (search) => {
  const history = { replaceState: vi.fn() };
  expect(
    readRoute(
      { pathname: "/mock-test", hostname: "localhost", search, hash: "" },
      history,
      true,
    ).scenario,
  ).toBe("invalid");
  expect(history.replaceState).toHaveBeenCalledWith(null, "", "/mock-test");
});
it("discards fragments and prevents unknown paths from entering history", () => {
  const history = { replaceState: vi.fn() };
  expect(
    readRoute(
      {
        pathname: "/mock-test",
        hostname: "localhost",
        search: "?preview=ready",
        hash: "#canary",
      },
      history,
      true,
    ).scenario,
  ).toBe("invalid");
  const route = readRoute(
    { pathname: "/secret-path", hostname: "localhost", search: "", hash: "" },
    history,
    true,
  );
  expect(route.page).toBe("not-found");
  expect(history.replaceState).toHaveBeenLastCalledWith(null, "", "/not-found");
});
