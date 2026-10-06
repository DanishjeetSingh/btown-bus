# To do

## Siri and Shortcuts (iOS)

Expose the app through App Intents so Siri, Shortcuts, the Action button, and Control Center can use it.

- Siri names for stops and routes (saved stops first), so "the IMU" and "the E" resolve.
- "When's the next bus at [stop]": spoken answer plus a small snippet card, without opening the app.
- "Track the [route] to [stop]": a `LiveActivityIntent`, which may start a Live Activity with the app in the background. That also gets around the "can only start while the app is open" limit, but a Siri-started activity begins right away instead of at N stops away.
- "Stop tracking".
- App Shortcuts phrases, which must include the app name. There's no transit schema domain, so free-form phrasing isn't guaranteed.
- Test phrase recognition on a real device; developers report it can be flaky right after install.

Docs: [LiveActivityIntent](https://developer.apple.com/documentation/appintents/liveactivityintent), [Siri and Apple Intelligence](https://developer.apple.com/documentation/AppIntents/Integrating-actions-with-siri-and-apple-intelligence), [WWDC26: App Schemas](https://developer.apple.com/videos/play/wwdc2026/240/).

## iOS efficiency

Items 1 and 2 are in `AppStore.swift` on the `codex/ios-ride-mode` branch (built and run in the simulator, not measured on a phone yet).

1. Only assign store data that actually changed, so every screen doesn't redraw every 15 s. Ignore arrival shifts under 30 s. Also keep a failed agency's buses on the map during an outage (bug fix).
2. Cache the Nearby list until you've moved about 15 m.
3. Share one short-lived bus-feed fetch between the tracker and the main screens.
4. While tracking, poll every 30–60 s and use coarse GPS until the bus or the stop is close.
5. Only update the Live Activity when something visible changes, plus about once a minute so it doesn't go stale.

## Maybe later

- Better predictions: log ETA Spot's predictions against when each bus actually reached the stop, then try an Apple Maps traffic-aware ETA (bus position to stop, plus time for each stop in between).
- Sharing with friends: SideStore, with a GitHub-hosted `.ipa` and source file for one-tap updates.
- Retake the README screenshots during service hours so buses show up on the map.
