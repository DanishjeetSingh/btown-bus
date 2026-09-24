import type { TransitRoute, TransitStop } from '@/src/transit/types';
import { leavePlan, type TrackedTrip, type TripStatus } from '@/src/transit/trip';
import { clockTime, routeStyle, shortClock } from '../lib/ui';
import { CloseIcon } from './icons';

type Props = {
  trip: TrackedTrip;
  status: TripStatus;
  route?: TransitRoute;
  stop?: TransitStop;
  walkMs?: number;
  atStop: boolean;
  now: number;
  onOpen: () => void;
  onEnd: () => void;
};

const LADDER = 6;

export default function TripCard({ trip, status, route, stop, walkMs, atStop, now, onOpen, onEnd }: Props) {
  const plan = status.arrival ? leavePlan(status.arrival.predictedArrival, walkMs, now, atStop) : undefined;
  const away = status.stopsAway;
  return (
    <aside className={`trip-card ${plan?.state ?? 'waiting'}`} style={routeStyle(route, trip.agency)} aria-live="polite">
      <button className="trip-main" type="button" onClick={onOpen}>
        <span className="route-block">{route?.shortName.trim() || trip.routeId}</span>
        <span className="trip-copy">
          <small>Tracking to</small>
          <strong>{stop?.name || 'your stop'}</strong>
          <span className="trip-leave">{plan ? plan.state === 'leave-soon' ? `Leave by ${clockTime(plan.leaveAt)}` : plan.label : status.arrival ? 'Turn on location for leave time' : 'Waiting for a prediction…'}</span>
        </span>
        <span className={`trip-eta ${(status.minutes ?? 0) >= 60 ? 'long' : ''}`}>{status.minutes == null || !status.arrival ? '—' : status.minutes === 0 ? 'Now' : status.minutes >= 60 ? shortClock(status.arrival.predictedArrival) : <>{status.minutes}<small>min</small></>}</span>
      </button>
      {away != null && <div className="stop-ladder" aria-label={`${away} ${away === 1 ? 'stop' : 'stops'} away`}>
        {Array.from({ length: LADDER }, (_, index) => {
          const position = LADDER - Math.min(away, LADDER);
          return <i key={index} className={index < position ? 'done' : index === position ? 'bus' : ''} />;
        })}
        <b>{away === 1 ? 'Next stop' : `${away} stops`}</b>
      </div>}
      <button className="trip-end" type="button" onClick={onEnd} aria-label="Stop tracking"><CloseIcon /></button>
    </aside>
  );
}
