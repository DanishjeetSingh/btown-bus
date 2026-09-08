# Repository review — September 8, 2026

Two delegated reviews covered the app's architecture and unused code, and the tracked files and available git history for public-release concerns. A follow-up cleanup fixed polling and freshness behavior, removed confirmed dead code, added MIT licensing, and added tests and lint to CI. Dependencies, preview tooling, and git history were preserved.

## What the repository does

A static Next.js app combines Bloomington Transit and IU Campus Bus on a Leaflet/MapLibre map. The browser validates and normalizes public ETA Spot responses, polls vehicles and stop arrivals, and stores route preferences and starred stops locally. GitHub Actions exports the app to `out/` and deploys it to GitHub Pages. The separate Vite/Sites configuration is not used by those npm scripts or the Pages workflow.

## Cleanup candidates

| Location | Finding | Suggested treatment |
| --- | --- | --- |
| `src/transit/freshness.ts` | Exported `toMillis()` has no callers in the app or transit modules. | Removed. |
| `src/transit/types.ts`, `src/transit/client.ts`, `app/page.tsx`, `app/globals.css` | Alert types, rendering, and styles exist, but the current adapter always returns an empty alerts array. | Removed the unused type, adapter fields, rendering branch, and CSS together. |
| `src/transit/types.ts` | Arrival `scheduledArrival`, the `scheduled` source variant, and arrival `tripId` are not populated by the current adapter. Vehicle `tripId` is used. | Removed the unpopulated arrival fields and unused source/freshness variants; retained vehicle trip IDs. |
| `src/transit/client.ts`, `app/page.tsx` | Route text color is always white, and the rendering fallback is also white. | Harmless redundancy; retaining it supports future route colors. |
| `vite.config.ts`, `package.json`, `tsconfig.json`, `.openai/hosting.json` | Vite, Vinext, Sites, and Cloudflare tooling is separate from the standard Next.js production path. | Keep until preview/hosting usage is established. Do not remove the dependency group merely because Pages does not invoke it. |
| `fixtures/bt/` | Older GTFS/protobuf samples are not loaded by application code or scripts. | Reference data, not shipped runtime code. Optional repository-size cleanup; preserve useful provenance. |

The fixture README's obsolete backend-proxy description was corrected. Historical reference fixtures were retained.

## Reliability fixes

- Shared serial polling replaces the independent initial request and timer loops. It waits for completion before scheduling again, skips hidden pages, and stops after cleanup even if a request completes late.
- Snapshot backoff uses provider status instead of relying on exceptions swallowed by the adapter. A healthy provider retains the normal interval during a partial outage.
- Total arrival-feed failure now rejects so the scheduler can back off. A successful empty response remains a success; partial results are still returned.
- Feed requests time out after 10 seconds. Retry delays double after failure and cap at 60 seconds.
- Arrival polling depends on stable agency/stop IDs, so vehicle refreshes do not reset it. Late results from a previous stop selection are ignored, and displayed arrivals are limited to the currently requested stops.
- Vehicle and arrival freshness are recomputed on the 15-second UI clock. Old data can become stale without another feed response.
- Starring a stop no longer throws when browser storage writes are unavailable.

## Public repository findings

- GitHub's API reported `DanishjeetSingh/btown-bus` as **PUBLIC** during this review. No visibility setting was changed.
- The delegated pattern scan found no credential matches in the 38 tracked files and 14 available commits, including eight deleted historical files. This is a bounded scan, not a guarantee that no sensitive material exists.
- Deleted deployment units remain in history: `deploy/btown-bus.service` and `deploy/cloudflared.service`, removed in commit `752d5e3`. They reveal an old server username, filesystem paths, a service port, and tunnel setup, but the review found no credentials there. Decide whether that historical operational detail is acceptable; no history rewrite was performed.
- Added an MIT `LICENSE` for the application and original documentation, with matching package metadata. The README distinguishes third-party data and assets from project licensing.
- The Pages workflow now runs lint and regression tests before building and deploying.
- Fixture redistribution terms were not established by this review. Public feed access does not itself document those terms.

The history review did not unpack binary fixtures or image metadata, inspect GitHub secrets, deploy keys, collaborators, or branch protection, or run a dependency vulnerability audit. Visibility was checked separately through `gh repo view`.

## Verification

- `npm test`: all five polling/freshness regression tests passed, covering backoff/reset, slow requests, cleanup, hidden pages, and aging.
- `npm run lint`: passed.
- `npm run build`: passed, including TypeScript and static export.
- `npm run validate:live`: passed for both agencies, including CORS checks.
- Chromium at 390 × 844: captured the actual route map, filters, and stop arrivals from the local production export using live feeds.
- Chromium at 375 × 812: route selection persisted after reload; arrivals panel collapse/expand worked; no horizontal document overflow or page errors observed.
- Simulated browser outage check passed: total-outage backoff, recovery with one provider unavailable, arrival rendering, hidden-page polling suspension, and aging of vehicle/arrival labels.
- Captured and visually inspected a 1440 × 960 desktop view.
- README local file/image links and `git diff --check`: passed.

These checks cover the documented flows, not every device, browser, network-failure mode, or installation path. Screenshots use mobile browser emulation rather than a physical phone.
