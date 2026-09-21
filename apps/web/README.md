# ExamCoach Web — W1

Independent React/TypeScript application inside the ExamCoach repository.
Version: `0.1.0`. Mobile stays `0.12.0+12`; no shared mobile bootstrap or assets.

## Run locally

Use Node **22.12 or newer within Node 22** and npm:

```bash
npm ci --prefix apps/web
npm run dev --prefix apps/web
```

Open `http://127.0.0.1:5173/profile`. Follow the tryout preview link or open
`/mock-test?preview=ready`. The local fixture panel exposes validating, ready,
claimed, expired, revoked, completed and invalid states. These names select
sample UI, never tokens or authorization. `validating` intentionally remains
pending until navigation. URL parameters are cleaned immediately, so refresh
returns the safe invalid state; actual same-browser session recovery is W3/W4.

`dev` explicitly selects `w1-preview` mode and `.env.w1-preview`. Fixtures also
require an exact loopback hostname. Default `npm run build --prefix apps/web`
has no fixture access. `/mock-test` fails closed; no W1 route opens questions.
No real profile login, link creation, cookie, storage, Firebase call, scoring,
autosave or submission is implemented. Do not distribute the fixture build.

## Quality gates

```bash
npm run check --prefix apps/web
npm exec --prefix apps/web -- playwright install chromium
npm run test:e2e --prefix apps/web
```

`check` runs Prettier, ESLint, strict TypeScript, unit/component tests and the
web build. Playwright builds both fixture and default variants in separate
output directories, then tests actual Chromium keyboard navigation, all states,
terminal redaction, URL cleanup, storage/network privacy, axe accessibility,
375/768/1024/1280/1440px reflow and 200% text. It does not record traces or
screenshots of capability input. Real screen-reader and Firefox/WebKit tests
remain W5. Do not reuse synthetic fixture tests as production security evidence.

## Boundaries

- `src/domain`: public landing response parser and repository interface.
- `src/data`: unavailable default and memory-only fake repositories.
- `src/route.ts`: allow-listed routes/fixture intake and history cleanup.
- `src/App.tsx`: profile and link-status presentation, no learning algorithms.
- `../../contracts/web-cbt`: language-neutral response schema; runtime/parser
  parity is tested. Regenerate with Node 22.18+ using
  `node --experimental-strip-types apps/web/tools/write-contract.mjs` from root,
  then run the formatter and tests. Cross-field time checks live in the parser.

Read [architecture](../../docs/architecture/Web_Platform_Architecture.md),
[delivery plan](../../docs/engineering/Web_Mock_Test_Delivery_Plan.md) and
[threat model](../../docs/engineering/Web_Link_Security_Threat_Model.md) before
implementing a real adapter. All backend development uses Firebase emulators
with a `demo-` project; no fallback to real services is allowed.
