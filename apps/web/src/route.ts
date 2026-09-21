import { linkStates, type LinkState } from "./domain/link-contract";

export type Page = "profile" | "mock-test" | "not-found";
export type Route = { page: Page; preview: boolean; scenario: LinkState };

export function isPreviewAllowed(enabled: boolean, hostname: string): boolean {
  return enabled && ["localhost", "127.0.0.1", "[::1]"].includes(hostname);
}

export function readRoute(
  location: Pick<Location, "pathname" | "hostname" | "search" | "hash">,
  history: Pick<History, "replaceState">,
  enabled: boolean,
): Route {
  const page: Page =
    location.pathname === "/" || location.pathname === "/profile"
      ? "profile"
      : location.pathname === "/mock-test"
        ? "mock-test"
        : "not-found";
  const preview = isPreviewAllowed(enabled, location.hostname);
  const params = new URLSearchParams(location.search);
  const candidate = params.get("preview");
  // Only one allow-listed fixture field, never capability-shaped input.
  const safeFixture =
    params.size === 1 &&
    !location.hash &&
    linkStates.some((value) => value === candidate);
  const scenario: LinkState =
    preview && safeFixture ? (candidate as LinkState) : "invalid";
  // W1 discards every query/fragment without validating or persisting a token.
  // Unknown paths are not reflected into UI, page titles or navigation history.
  history.replaceState(
    null,
    "",
    page === "not-found" ? "/not-found" : `/${page}`,
  );
  return { page, preview, scenario };
}
