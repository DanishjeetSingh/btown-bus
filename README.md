# B-Town Bus

A fast, mobile-first tracker that combines Bloomington Transit and IU Campus Bus in one map. It is an independent third-party project and is not affiliated with Bloomington Transit or Indiana University.

## What it does

- Shows current BT and IU vehicles, route paths, and stops on one map
- Finds nearby stops after optional location permission
- Displays realtime and scheduled arrivals with honest freshness labels
- Shows direction, walking time, and a conservative “leave now” estimate
- Filters routes, saves favorite stops locally, and keeps working when one provider fails
- Polls vehicle data every 15 seconds and arrival data every 25 seconds, slowing down when hidden or after errors

## Data

Bloomington Transit uses its official static GTFS and GTFS-Realtime feeds. IU Campus Bus uses the public ETA Spot JSON endpoints. Provider-specific data is normalized in `src/transit/adapters` before it reaches the UI. Captured public-feed fixtures are under `fixtures/`.

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

Production checks:

```bash
npm run lint
npm run build
```

## Reliability notes

The app does not calculate its own bus ETA. It prefers provider predictions, falls back to BT schedule data, marks realtime positions stale after 90 seconds, and shows an unavailable state instead of inventing information. No API keys or private credentials are required or committed.
