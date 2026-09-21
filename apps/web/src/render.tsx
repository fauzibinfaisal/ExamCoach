import { createRoot } from "react-dom/client";
import { App } from "./App";
import {
  FakeLinkRepository,
  UnavailableLinkRepository,
} from "./data/link-repository";
import type { Route } from "./route";
import "./styles.css";

export function render(route: Route) {
  const repository = route.preview
    ? new FakeLinkRepository(route.scenario)
    : new UnavailableLinkRepository();
  createRoot(document.getElementById("root")!).render(
    <App route={route} repository={repository} />,
  );
}
