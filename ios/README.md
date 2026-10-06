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
- The Live Activity starts once the bus is within your stop count. It starts earlier if your walk means you need to leave before then. It alerts you at **Leave now** and when the bus is **arriving**. Once you say you're on, it follows the ride and tells you when to ring the bell.
- **At the stop.** When you're within about 40 m of the stop, allowing for GPS accuracy, the app and the Live Activity switch to *You're at the stop*. Walk time drops to zero and the leave countdown stops.

## How tracking works (and its limits)

There is no server, so the app does the tracking itself. While a trip is active, it keeps location updates running in the background (the blue location pill). That keeps the app awake so it can check the feeds every 10–15 seconds, update the Live Activity, and notice when you reach the stop. Tracking stays active for boarding confirmation after the bus passes. End the trip manually if you miss the bus. Trips expire after two hours.

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

## The trip screen

Tap the trip banner (or **Walk here** on any stop) to open the trip sheet. It's laid out like a stop's page: a header, a live map card, then the usual cards and rows. The map card keeps you, your stop (yellow dot), and the bus in view as they move; pan it to look around, and tap the corner button to bring all three back.

- **Walking to the stop.** The next turn from Apple Maps walking directions, the When-to-go card for your bus, and the bus with how many stops away it is. From **Walk here** without a tracked bus, it lists the buses due at that stop with **Track** buttons.
- **I'm on the bus.** Pick where you're getting off from the stops this bus will actually make next. If the bus has already pulled away when the app notices, it asks whether you caught it; **Missed it** switches to the next bus on the route.
- **Riding.** A count of stops to go, the stops left with yours marked, and a **Ring the bell** card (plus a notification and Live Activity alert) when yours is next. Near your stop it says **Get off here**.

The Map tab also has a **you + bus** button while you're tracking, which frames you and the bus together and follows both until you pan.

Ride progress moves forward from the bus feed (its next stop) and from your phone's GPS (arriving at a stop, then leaving it), one stop at a time, so a stop the route passes twice can't make it skip ahead. Your phone's position is never shown as the bus.

**Start walking** opens turn-by-turn walking like Apple Maps: a tilted 3D map that follows you and turns as you do, the next turn at the top, and your walk against the bus at the bottom ("4 min to spare"). It keeps the screen awake and buzzes at each turn. Walking directions use the fastest Apple Maps route; **Use a different walking route** picks another, remembered for that stop. Guidance is silent; **Apple Maps** hands off to Apple's spoken directions.

## How stops away is counted

ETA Spot gives each bus a pattern (one direction or branch of a route), its next stop, the stop it just left, and a short list of its next few stops. The route's own stop list mixes both directions and every branch, so it can't be used for counting. Instead the app:

1. Finds the bus in its pattern. A stop the pattern passes twice is told apart by the stop the bus just left.
2. Walks forward from there, wrapping around loop patterns (IU) and continuing into the pattern that starts where this one ends (Bloomington Transit buses turn around and run the other direction).
3. Checks the result against the feed's own next stops. If the reported pattern doesn't fit (it lags behind a turnaround), it tries the route's other patterns and accepts exactly one that does.

If the bus's position can't be pinned down, no count is shown rather than a wrong one; the arrival time still is. The same rules live in `src/transit/trip.ts` for the web app. Run the iOS model checks with:

```sh
scripts/check-ios-journey.sh
```
