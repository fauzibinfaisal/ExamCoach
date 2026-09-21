import { readRoute } from "./route";

// Clean incoming URL before loading/rendering the application. No telemetry SDK.
const route = readRoute(
  window.location,
  window.history,
  import.meta.env.MODE === "w1-preview" &&
    import.meta.env.VITE_W1_PREVIEW === "true",
);
void import("./render").then(({ render }) => render(route));
