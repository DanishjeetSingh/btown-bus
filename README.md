# B-Town Bus

A fast, mobile-first tracker that combines Bloomington Transit and IU Campus Bus in one map. It is an independent third-party project and is not affiliated with Bloomington Transit or Indiana University.

## What it does

- Shows current BT and IU vehicles, route paths, and stops on one map
- Finds nearby stops after optional location permission
- Displays provider-supplied realtime arrivals with honest freshness labels
- Shows direction, walking time, and a conservative “leave now” estimate
- Filters routes, saves favorite stops locally, and keeps working when one provider fails
- Polls vehicle data every 15 seconds and arrival data every 25 seconds, slowing down when hidden or after errors

## Data

The GitHub Pages app reads the public, browser-safe ETA Spot JSON feeds for Bloomington Transit and IU Campus Bus. Provider-specific data is validated and normalized in `src/transit/client.ts` before it reaches the UI. Captured public-feed fixtures are under `fixtures/`.

## Development

Requires Node.js 22.13 or newer.

```bash
npm install
npm run dev
```

Then open `http://localhost:3000`. With the development server running, verify both upstreams with:

```bash
npm run validate:live
```

On iPhone or iPad, open `https://btb.singhdan.me` in Safari, tap Share, and choose **Add to Home Screen**. The installed app uses a dedicated home-screen icon, opens without Safari chrome, respects the device safe area, and keeps an offline shell while never caching live transit API responses.

Production checks:

```bash
npm run lint
npm run build
```

## Deployment

Pushes to `main` are built and published by `.github/workflows/pages.yml` to GitHub Pages at `https://btb.singhdan.me`. Production does not run on LAIR or require a long-lived application server.

## Reliability notes

The app does not calculate its own bus ETA. It uses provider predictions, marks realtime positions stale after 90 seconds, and shows an unavailable state instead of inventing information. It is a static GitHub Pages deployment with no server process, API keys, or committed credentials.
