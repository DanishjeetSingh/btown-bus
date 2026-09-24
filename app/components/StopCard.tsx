import type { TransitArrival, TransitRoute, TransitStop } from '@/src/transit/types';
import { formatDistance, walkSeconds } from '@/src/transit/trip';
import { agencyName, minutesUntil, routeKey, routeStyle, shortClock } from '../lib/ui';
import { StarIcon } from './icons';

type Props = {
  stop: TransitStop;
  arrivals: TransitArrival[];
  routeMap: Map<string, TransitRoute>;
  now: number;
  distance?: number;
  atStop?: boolean;
  loading?: boolean;
  favorite: boolean;
  onOpen: () => void;
  onToggleFavorite: () => void;
};

export default function StopCard({ stop, arrivals, routeMap, now, distance, atStop, loading, favorite, onOpen, onToggleFavorite }: Props) {
  const next = arrivals.slice(0, 4);
  return (
    <article className={`stop-card ${stop.agency} ${atStop ? 'here' : ''}`}>
      <button className="stop-card-main" type="button" onClick={onOpen}>
        <span className="stop-card-title">
          <strong>{stop.name}</strong>
          <small>
            <i className={`agency-dot ${stop.agency}`} />{agencyName(stop.agency)}
            {atStop ? <b className="here-tag">You&apos;re here</b> : distance != null && <> · {formatDistance(distance)} · {Math.max(1, Math.round(walkSeconds(distance) / 60))} min walk</>}
          </small>
        </span>
        <span className="chip-row">
          {next.length ? next.map((arrival, index) => {
            const route = routeMap.get(routeKey(arrival.agency, arrival.routeId));
            const minutes = minutesUntil(arrival.predictedArrival, now);
            return <span className={`time-chip ${index === 0 ? 'first' : ''}`} key={`${arrival.routeId}:${arrival.vehicleId ?? index}`} style={routeStyle(route, arrival.agency)}>
              <b>{route?.shortName.trim() || arrival.routeId}</b>
              <span>{minutes === 0 ? 'Now' : minutes >= 60 ? shortClock(arrival.predictedArrival) : <>{minutes}<small>m</small></>}</span>
            </span>;
          }) : <span className="chip-empty">{loading ? 'Checking times…' : 'No buses due soon'}</span>}
        </span>
      </button>
      <button className={`star-button ${favorite ? 'on' : ''}`} type="button" aria-pressed={favorite} aria-label={favorite ? `Remove ${stop.name} from saved stops` : `Save ${stop.name}`} onClick={onToggleFavorite}><StarIcon filled={favorite} /></button>
    </article>
  );
}
