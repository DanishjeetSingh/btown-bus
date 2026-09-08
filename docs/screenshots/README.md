# App screenshots

Captured September 8, 2026 from a local production export (`npm run build`), served at localhost. The app used the live public ETA Spot feeds and its normal map services. No feed responses or arrival times were mocked.

- `mobile-map.png`: IU F selected, arrivals collapsed, routes re-centered.
- `mobile-routes.png`: route picker open with IU F selected.
- `mobile-stop.png`: Alumni Center stop selected, showing provider arrivals.
- `desktop.png`: the same stop at a wider viewport.

Mobile captures use Chromium with a 390 × 844 CSS-pixel viewport, touch/mobile emulation, and a device scale factor of 2. The desktop capture uses a 1440 × 960 viewport at the same scale. These are browser viewport captures, not physical-device screenshots. Location permission was not granted; walking distances use the app's downtown default.

To refresh them, serve a production build, select an operating route, and wait for both the map and live data to load. Capture the map, route picker, and a stop with arrivals. Preserve the unmodified UI and update the date in the main README. Check that the images contain no browser chrome, personal location, or unrelated windows.
