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
- The Live Activity starts once the bus is within your stop count. It starts earlier if your walk means you need to leave before then. It alerts you at **Leave now** and when the bus is **arriving**, then asks whether you boarded after the bus passes your pickup stop.
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

## Walking guidance and ride mode

Open any stop and tap **Walk to stop**, even when no buses are running. Walking is independent of bus tracking and ends when you close the walking screen. It keeps GPS active while that screen is open, including in the background. You can also access it from the tracked journey options. **Walk to stop** requests an Apple Maps walking route and shows it on the journey map and main map. The full-screen map opens at your GPS position with a close 240 m camera and 55° pitch, then follows your position and heading. Panning pauses following; Recenter restores it. Navigation cards and controls use the existing yellow/cream/ink palette, expanded typography, outlined shapes, and hard shadows. A turn card shows the upcoming maneuver and distance; the bottom panel shows remaining distance, estimated time, and arrival time. GPS is projected along the route to advance guidance. Three accurate off-route fixes trigger rerouting, with requests limited to once per 30 seconds. Controls provide route overview, recentering, a Steps sheet, and End. **Navigate in Apple Maps** opens Apple's walking navigation for spoken guidance; in-app guidance is silent.

After boarding, tap **I'm on board · Choose my stop** and confirm your destination. Destinations come from the selected bus's active direction/branch pattern, not the combined route stop list. If a pickup repeats in the pattern, choose the pickup visit. Known circular patterns support destinations across the end of the list; non-circular patterns do not wrap. Boarding needs a fresh selected vehicle with pattern data.

Ride mode uses accurate GPS fixes less than 20 seconds old and checks the selected vehicle every 15 seconds. It advances through specific stop visits after entering and departing a stop, or after observing the corresponding next-stop transition in a fresh bus feed. It never publishes your phone's position as the bus's location. A notification, foreground haptic, and Live Activity state prompt **Request your stop now** after departing the preceding stop. Near the destination, it asks **Did you get off?**; **I got off · End trip** confirms the end manually. No accelerometer or automatic boarding/exit detection is used.

Location gaps, skipped stops, detours, and feed errors can delay reminders. Background execution and notification delivery depend on iOS permissions and scheduling. Ride reminders require on-device validation before relying on them during a journey.

## Stop-count correctness

Both clients request `get_patterns` and retain vehicle `patternID` and ordered `minutesToNextStops`. Stop counts prefer the vehicle's upcoming stop predictions, then its active pattern if the prediction prefix agrees. Repeated visits must yield an unambiguous count; only patterns explicitly marked circular wrap. Missing or conflicting data yields no stop count while the arrival ETA remains available. The combined `get_routes.stops` list is used for route membership, not counting a particular bus's remaining stops.

Run the iOS model regression checks on macOS:

```sh
scripts/check-ios-journey.sh
```

On an iPhone, verify walking-route refresh, a real boarding transition, notification delivery while locked, the reminder after the preceding stop, and manual exit. Also test denied permissions, feed loss, repeated pickup visits, and a circular route crossing its list boundary.

## Walking Live Activity

Starting navigation on a selected walking route starts its own Live Activity while the app is open. The Lock Screen shows the next maneuver, turn distance, stop name, remaining minutes/distance, and estimated arrival. Dynamic Island includes compact, minimal, and expanded walking layouts in the app's ink/cream/yellow style. GPS callbacks update navigation and the activity directly while the phone is locked. Updates are limited to every five seconds, except maneuver and phase changes. The activity becomes stale after 45 seconds without an accurate GPS fix.

Arrival changes the activity to **You're here**. **End walk** on the Lock Screen/Dynamic Island ends navigation and its GPS session; ending in the app removes the activity too. Bus and walking activities are independent. If Live Activities are disabled or can't start, the walking screen explains it. Walking sessions aren't restored after process termination; orphaned activities are cleaned up on the next launch.

## Remembered walking routes

Walking guidance is silent. Apple Maps is asked for alternate walking routes. The first walk to a stop shows every returned path on the map with its name, time, and distance. Select a path and tap **Use this route**. The app remembers that path separately for each agency/stop and uses it automatically on later walks when it can match the freshly returned route by name and corridor. Route array order is never used as an identity. Unavailable or ambiguous preferences show the picker again. Use the walking menu's **Choose a different route** to replace the preference. Apple may return only one walking route for a particular origin/destination.
