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

## Our own arrival predictions

The collector (`collector/`) has been recording both feeds on `ash` since 2026-11-06. Start around 2026-11-20, once there are two weeks of data.

1. **Stretch times.** Pair each bus's consecutive "left a stop" events into stop-to-stop travel times. Tag each with route, direction, time of day, weekday, and special days (Thanksgiving break, finals, game days). Drop buses that left service mid-route, frozen GPS, and stops the feed skipped.
2. **Grade the feed.** Match every logged feed prediction to when that bus really reached the stop. Report error by route, time of day, and how far ahead (2–20 min). This is the number to beat.
3. **Version 1: typical times.** Median time per stretch per 30-minute slot, weekdays and weekends separately. Predict by adding up the stretches ahead of the bus, each for the slot it'll be in. Build from the first ~10 days, test on the rest, against the feed and the in-app Apple Maps estimate.
4. **Ship it if it wins.** The server rebuilds a small file of stretch times nightly; the app (and the website) download it daily and work out arrivals themselves, with no live server. Make it the big number once it beats the feed consistently, with the feed's time as the second opinion.
5. **Use the spread, not just the average.** Arrival ranges ("5–8 min"), a leave time that catches the bus 9 times out of 10, reliability notes ("the 6 runs ~3 min late around 5 PM"), and spotting ghost buses that aren't moving.
6. **Version 2, only if version 1 proves out.** Adjust live when the last few buses through a stretch were slower than usual. Needs the server publishing every minute.

## gork (OpenClaw agent) integration

- A tool gork can call for "when should I leave for work?" (live buses, walk times, and ride times from the prediction model).
- A weekday job where gork messages me when to leave.
- A "track this bus" link gork can send: a URL B-Town Bus handles, plus an https redirect page on the website so chat apps make it tappable. Starting with no tap needs a paid account (push).

## Maybe later

- Sharing with friends: SideStore, with a GitHub-hosted `.ipa` and source file for one-tap updates.
- Retake the README screenshots during service hours so buses show up on the map.
