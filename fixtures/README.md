# Public feed fixtures

These files were captured from public Bloomington Transit and IU Campus Bus endpoints on August 26, 2026. They are reference samples, not runtime data or an automated test suite.

- `bt/` contains a GTFS archive and GTFS-Realtime protobuf captures from earlier feed investigation.
- `iu/` contains ETA Spot JSON responses for routes, patterns, stops, vehicles, and arrivals.

The current app reads both agencies' browser-accessible ETA Spot feeds directly in `src/transit/client.ts`. It does not use a backend proxy or load these fixtures. The older Bloomington GTFS-Realtime endpoint's CORS restrictions do not describe the current ETA Spot integration.

Transit data belongs to its respective providers; public access alone does not establish redistribution terms.
