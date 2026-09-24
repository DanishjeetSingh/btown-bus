import type { TransitArrival, TransitRoute, TransitStop, TransitVehicle } from '@/src/transit/types';
import { formatDistance, leavePlan, stopsAway, type TrackedTrip } from '@/src/transit/trip';
import type { LocationStatus } from '../hooks/useLiveLocation';
import { agencyName, clockTime, minutesUntil, routeKey, routeStyle, shortClock } from '../lib/ui';
import { CloseIcon, LocateIcon, MapIcon, StarIcon, WalkIcon } from './icons';

type Props = {
  stop: TransitStop;
  arrivals: TransitArrival[];
  routeMap: Map<string, TransitRoute>;
  vehicles: TransitVehicle[];
  now: number;
  distance?: number;
  walkMs?: number;
  atStop: boolean;
  locationStatus: LocationStatus;
  favorite: boolean;
  trip?: TrackedTrip;
  overMap: boolean;
  loading: boolean;
  onClose: () => void;
  onToggleFavorite: () => void;
  onTrack: (arrival: TransitArrival) => void;
  onShowMap: () => void;
  onEnableLocation: () => void;
};

export default function StopSheet(props: Props) {
  const { stop, arrivals, routeMap, vehicles, now, distance, walkMs, atStop, locationStatus, favorite, trip, overMap, loading } = props;
  const first = arrivals[0];
  const plan = first ? leavePlan(first.predictedArrival, walkMs, now, atStop) : undefined;
  const servingRoutes = (stop.routeIds ?? []).map((id) => routeMap.get(routeKey(stop.agency, id))).filter((route): route is TransitRoute => Boolean(route));
  const firstRoute = first && routeMap.get(routeKey(first.agency, first.routeId));

  return (
    <section className={`stop-sheet ${overMap ? 'over-map' : ''}`} role="dialog" aria-modal="false" aria-labelledby="stop-sheet-title">
      <div className="sheet-grip" aria-hidden="true" />
      <header className="stop-sheet-head">
        <div>
          <p className="eyebrow"><i className={`agency-dot ${stop.agency}`} />{agencyName(stop.agency)} stop</p>
          <h2 id="stop-sheet-title">{stop.name}</h2>
          {servingRoutes.length > 0 && <div className="route-pills">{servingRoutes.map((route) => <span key={route.id} style={routeStyle(route, route.agency)}>{route.shortName.trim()}</span>)}</div>}
        </div>
        <button className="icon-button" type="button" onClick={props.onClose} aria-label="Close stop"><CloseIcon /></button>
      </header>

      <div className="sheet-actions">
        <button className={`big-toggle ${favorite ? 'on' : ''}`} type="button" aria-pressed={favorite} onClick={props.onToggleFavorite}><StarIcon filled={favorite} />{favorite ? 'Saved' : 'Save stop'}</button>
        {!overMap && <button className="big-toggle" type="button" onClick={props.onShowMap}><MapIcon />Map</button>}
      </div>

      {atStop ? <div className="walk-strip here"><span className="pulse" />You&apos;re at this stop</div>
        : distance != null ? <div className="walk-strip"><WalkIcon />{Math.max(1, Math.round((walkMs ?? 0) / 60_000))} min walk <span>· {formatDistance(distance)}</span></div>
        : locationStatus === 'denied' ? <button className="walk-strip muted" type="button" onClick={props.onEnableLocation}>Location is blocked. Allow it for this site in Settings, then tap to retry.</button>
        : <button className="walk-strip action" type="button" onClick={props.onEnableLocation}><LocateIcon />Turn on location for walk times</button>}

      {plan && first && <div className={`leave-card ${plan.state}`} style={routeStyle(firstRoute, first.agency)}>
        <div>
          <span className="leave-kicker">{plan.state === 'at-stop' ? 'Next bus' : plan.state === 'too-late' ? 'Heads up' : 'When to go'}</span>
          <strong>{plan.state === 'at-stop' ? `${firstRoute?.shortName.trim() || first.routeId} ${minutesUntil(first.predictedArrival, now) >= 60 ? `at ${shortClock(first.predictedArrival)}` : `in ${minutesUntil(first.predictedArrival, now)} min`}` : plan.state === 'leave-soon' && plan.minutesUntilLeave >= 60 ? `Leave at ${shortClock(plan.leaveAt)}` : plan.label}</strong>
          <span className="leave-sub">{plan.state === 'at-stop' ? 'Stay put — it’s on the way.' : plan.state === 'too-late' ? 'Catch the one after, or run.' : `Leave by ${clockTime(plan.leaveAt)} for the ${clockTime(first.predictedArrival)} ${firstRoute?.shortName.trim() || ''}`.trim()}</span>
        </div>
      </div>}

      <h3 className="section-label">Arriving</h3>
      <ol className="arrival-list">
        {arrivals.length ? arrivals.slice(0, 10).map((arrival, index) => {
          const route = routeMap.get(routeKey(arrival.agency, arrival.routeId));
          const vehicle = arrival.vehicleId ? vehicles.find((item) => item.agency === arrival.agency && item.id === arrival.vehicleId) : undefined;
          const away = vehicle ? stopsAway(route?.stopIds, vehicle.nextStopId, stop.id) : undefined;
          const minutes = minutesUntil(arrival.predictedArrival, now);
          const tracking = trip && trip.agency === arrival.agency && trip.stopId === arrival.stopId && trip.routeId === arrival.routeId && (!trip.vehicleId || trip.vehicleId === arrival.vehicleId);
          return <li className={`arrival-row ${tracking ? 'tracking' : ''}`} key={`${arrival.routeId}:${arrival.vehicleId ?? index}`} style={routeStyle(route, arrival.agency)}>
            <span className="route-block">{route?.shortName.trim() || arrival.routeId}</span>
            <span className="arrival-copy">
              <strong>{arrival.destination || route?.longName || 'Direction unavailable'}</strong>
              <small>{away != null ? `${away} ${away === 1 ? 'stop' : 'stops'} away` : route?.longName || ''}{vehicle?.freshness === 'stale' ? ' · signal lost' : ''}</small>
            </span>
            <span className="arrival-time"><strong>{minutes === 0 ? 'Now' : minutes >= 60 ? shortClock(arrival.predictedArrival) : minutes}</strong>{minutes > 0 && minutes < 60 && <small>min</small>}</span>
            <button className="track-button" type="button" aria-pressed={Boolean(tracking)} onClick={() => props.onTrack(arrival)}>{tracking ? 'Tracking' : 'Track'}</button>
          </li>;
        }) : <li className="empty-note">{loading ? 'Checking arrival times…' : 'No buses predicted for this stop right now.'}</li>}
      </ol>
      <p className="fine-print">Predictions come from the transit feeds and can change. Walk times assume a steady pace along a slightly padded straight line.</p>
    </section>
  );
}
