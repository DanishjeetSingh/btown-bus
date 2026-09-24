# Screenshots

Taken September 24, 2026, around 2 AM, so no buses were running. That's why the map says "No buses running" and every arrival is a morning time. The times are real feed predictions, not mocked.

- `web-*.png`: the production build (`npm run build`) served locally in headless Chrome. Mobile shots are 390 × 844 at 3×; desktop is 1440 × 900 at 2×, resized to 1600 px wide. Location was faked to a spot near the IMU.
- `ios-*.png`: the iOS app in the iPhone 17 simulator, with the simulator's location set near the IMU. The Live Activity shot uses the debug-only `-demoLiveActivity` launch argument, because there was no real bus to track at that hour.

When you retake them, do it during service hours so there are buses on the map.
