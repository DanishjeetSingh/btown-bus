# B-Town Bus for iPhone

A native SwiftUI version of B-Town Bus, with a Live Activity that follows one bus to one stop.

## What it does

- **Saved, Nearby, Map** tabs, matching the web app. Starred stops show live times on the Saved tab.
- **Track a bus.** On any stop, tap **Track** next to an arrival, choose *this bus* or *the next bus on the route*, and choose how many stops away to start (default 5).
- **Live Activity** on the Lock Screen and Dynamic Island shows:
  - a countdown until the bus reaches your stop
  - how many stops away it is
  - your walk time, from Apple Maps walking directions
  - when to leave
- The Live Activity starts once the bus is within your stop count. It starts earlier if your walk means you need to leave before then. It alerts you at **Leave now** and when the bus is **arriving**, then ends itself a couple of minutes after the bus passes your stop.
- **At the stop.** When you're within about 40 m of the stop, allowing for GPS accuracy, the app and the Live Activity switch to *You're at the stop*. Walk time drops to zero and the leave countdown stops.

## How tracking works (and its limits)

There is no server, so the app does the tracking itself. While a trip is active, it keeps location updates running in the background (the blue location pill). That keeps the app awake so it can check the feeds every 10–15 seconds, update the Live Activity, and notice when you reach the stop. Tracking stops by itself after the bus passes, or after two hours.

iOS only lets an app *start* a Live Activity while it's on screen, unless a push server starts it. If the bus reaches your stop count while the app is in the background, you get a notification instead ("6 is 5 stops away — Leave by 7:12"). The Live Activity then starts the next time you open the app. If you want the Live Activity from the beginning, start tracking when the bus is already close, or open the app when the notification arrives.

If location permission is off, the app still tracks, but iOS may pause it in the background. The Live Activity is marked stale after three minutes without an update, so old times never look current.

## Build and run

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
cd ios
xcodegen generate
open BTownBus.xcodeproj
```

Choose the **BTownBus** scheme and your iPhone, then press Run. The project signs with team `FY8QPUD5XV`; change `DEVELOPMENT_TEAM` in `project.yml` to use another account. With a free Apple ID, the app has to be reinstalled every 7 days.

In the simulator, use Features → Location to fake a position near a stop and test *You're at the stop*. Debug builds also accept a `-demoLiveActivity` launch argument that starts a sample Live Activity, which is handy at night when nothing is running.

## Layout

| Path | Purpose |
| --- | --- |
| `BTownBus/Model` | Feed client (ETA Spot, both agencies), shared types, and trip math, the same rules as `src/transit/trip.ts` |
| `BTownBus/Services/LocationService.swift` | One location manager; background updates only while tracking; walking ETAs |
| `BTownBus/Services/TripTracker.swift` | The trip loop: stops away, leave time, at-stop, Live Activity start/update/end, fallback notifications |
| `BTownBus/Services/AppStore.swift` | Routes, stops, vehicles, arrivals, favorites, and route choices |
| `BTownBusWidgets` | Lock Screen and Dynamic Island UI for the Live Activity |
| `Shared` | Live Activity attributes and the End button intent, used by both targets |
