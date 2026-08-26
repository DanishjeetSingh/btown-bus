'use client';

import dynamic from 'next/dynamic';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { getClientArrivals, getClientSnapshot } from '@/src/transit/client';
import type { TransitArrival, TransitRoute, TransitSnapshot, TransitStop } from '@/src/transit/types';

const TransitMap = dynamic(() => import('./components/TransitMap'), { ssr: false, loading: () => <div className="map-loading"><span />Loading live map…</div> });
const DEFAULT_POSITION: [number, number] = [39.1699, -86.5258];
const routeKey = (agency: string, id: string) => `${agency}:${id}`;
const stopKey = (stop: TransitStop) => `${stop.agency}:${stop.id}`;

export default function Home() {
  const [snapshot, setSnapshot] = useState<TransitSnapshot>();
  const [position, setPosition] = useState<[number, number]>();
  const [locationError, setLocationError] = useState('');
  const [selectedStop, setSelectedStop] = useState<TransitStop>();
  const [arrivals, setArrivals] = useState<TransitArrival[]>([]);
  const [activeRoutes, setActiveRoutes] = useState<Set<string>>(new Set());
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [favoriteKeys, setFavoriteKeys] = useState<Set<string>>(new Set());
  const [now, setClock] = useState(() => Date.now());

  const loadSnapshot = useCallback(async () => {
    try {
      const next = await getClientSnapshot();
      setSnapshot(next);
      setActiveRoutes((current) => current.size ? current : new Set(next.routes.map((route) => routeKey(route.agency, route.id))));
    } catch { setSnapshot((current) => current ?? { routes: [], stops: [], vehicles: [], alerts: [], sources: [{ agency: 'bt', ok: false, updatedAt: Date.now() }, { agency: 'iu', ok: false, updatedAt: Date.now() }], generatedAt: Date.now() }); }
  }, []);

  useEffect(() => {
    const initial = setTimeout(loadSnapshot, 0);
    let failures = 0;
    let timer: ReturnType<typeof setTimeout>;
    const poll = async () => {
      if (!document.hidden) {
        try { await loadSnapshot(); failures = 0; } catch { failures += 1; }
      }
      timer = setTimeout(poll, Math.min(60_000, 15_000 * 2 ** failures));
    };
    timer = setTimeout(poll, 15_000);
    return () => { clearTimeout(initial); clearTimeout(timer); };
  }, [loadSnapshot]);

  useEffect(() => {
    const initial = setTimeout(() => {
      try { setFavoriteKeys(new Set(JSON.parse(localStorage.getItem('btown-bus-favorites') || '[]'))); } catch { /* ignore damaged local preference */ }
    }, 0);
    const timer = setInterval(() => setClock(Date.now()), 15_000);
    return () => { clearTimeout(initial); clearInterval(timer); };
  }, []);

  const originLat = position?.[0] ?? DEFAULT_POSITION[0];
  const originLng = position?.[1] ?? DEFAULT_POSITION[1];
  const origin: [number, number] = [originLat, originLng];
  const nearbyStops = useMemo(() => (snapshot?.stops ?? [])
    .map((stop) => ({ stop, distance: distanceMeters([originLat, originLng], [stop.lat, stop.lng]) }))
    .sort((a, b) => a.distance - b.distance).slice(0, 8), [snapshot?.stops, originLat, originLng]);

  const requestedStops = useMemo(() => selectedStop ? [selectedStop] : nearbyStops.slice(0, 4).map((item) => item.stop), [nearbyStops, selectedStop]);
  const requestedKey = requestedStops.map(stopKey).join(',');
  useEffect(() => {
    if (!requestedKey) return;
    let cancelled = false;
    const load = async () => {
      try {
        const next = await getClientArrivals(requestedStops.map((stop) => ({ agency: stop.agency, id: stop.id })));
        if (!cancelled) setArrivals(next);
      } catch { if (!cancelled) setArrivals([]); }
    };
    load();
    const timer = setInterval(load, 25_000);
    return () => { cancelled = true; clearInterval(timer); };
  }, [requestedKey, requestedStops]);

  const locate = () => {
    setLocationError('');
    if (!navigator.geolocation) return setLocationError('Location is not available in this browser.');
    navigator.geolocation.getCurrentPosition(
      ({ coords }) => setPosition([coords.latitude, coords.longitude]),
      () => setLocationError('Location permission was not granted. Showing downtown Bloomington.'),
      { enableHighAccuracy: true, timeout: 10_000, maximumAge: 30_000 },
    );
  };

  const routeMap = useMemo(() => new Map((snapshot?.routes ?? []).map((route) => [routeKey(route.agency, route.id), route])), [snapshot?.routes]);
  const displayArrivals = arrivals.filter((arrival) => activeRoutes.has(routeKey(arrival.agency, arrival.routeId))).slice(0, selectedStop ? 8 : 6);
  const selectedDistance = selectedStop ? distanceMeters(origin, [selectedStop.lat, selectedStop.lng]) : undefined;
  const firstArrival = displayArrivals[0];
  const leaveText = firstArrival && selectedDistance != null ? getLeaveText(firstArrival.predictedArrival, selectedDistance, now) : undefined;
  const overallOk = snapshot?.sources.some((source) => source.ok);

  const toggleAgency = (agency: 'bt' | 'iu') => setActiveRoutes((current) => {
    const next = new Set(current);
    const agencyKeys = (snapshot?.routes ?? []).filter((route) => route.agency === agency).map((route) => routeKey(route.agency, route.id));
    const turnOn = agencyKeys.some((item) => !next.has(item));
    agencyKeys.forEach((item) => { if (turnOn) next.add(item); else next.delete(item); });
    return next;
  });
  const toggleRoute = (route: TransitRoute) => setActiveRoutes((current) => {
    const next = new Set(current); const item = routeKey(route.agency, route.id); if (next.has(item)) next.delete(item); else next.add(item); return next;
  });
  const toggleFavorite = (stop: TransitStop) => {
    const next = new Set(favoriteKeys); const item = stopKey(stop); if (next.has(item)) next.delete(item); else next.add(item);
    setFavoriteKeys(next); localStorage.setItem('btown-bus-favorites', JSON.stringify([...next]));
  };

  return (
    <main className="tracker-shell">
      <header className="topbar">
        <a className="brand" href="#" onClick={() => setSelectedStop(undefined)} aria-label="B-Town Bus home"><span className="brand-mark">B</span><span><strong>B-Town Bus</strong><small>Bloomington + IU</small></span></a>
        <div className="header-actions">
          <button className="filter-button" type="button" aria-expanded={filtersOpen} onClick={() => setFiltersOpen(!filtersOpen)}>Routes <b>{activeRoutes.size}</b></button>
          <button className="location-button" type="button" onClick={locate}><span aria-hidden="true">◎</span><em>Use my location</em></button>
        </div>
      </header>

      {filtersOpen && <section className="filter-panel" aria-label="Route filters">
        <div className="agency-filters"><button type="button" onClick={() => toggleAgency('iu')}>IU Campus Bus</button><button type="button" onClick={() => toggleAgency('bt')}>Bloomington Transit</button></div>
        <div className="route-filters">{snapshot?.routes.map((route) => <button key={routeKey(route.agency, route.id)} className={activeRoutes.has(routeKey(route.agency, route.id)) ? 'active' : ''} style={{ '--route': route.color } as React.CSSProperties} type="button" onClick={() => toggleRoute(route)}><i />{route.shortName}</button>)}</div>
      </section>}
      {locationError && <div className="toast" role="status">{locationError}<button onClick={() => setLocationError('')} aria-label="Dismiss">×</button></div>}
      {snapshot?.alerts[0] && <div className="alert-strip"><b>Service alert</b><span>{snapshot.alerts[0].title || snapshot.alerts[0].description}</span></div>}

      <section className="map-stage" aria-label="Live Bloomington transit map">
        {snapshot ? <TransitMap routes={snapshot.routes} stops={snapshot.stops} vehicles={snapshot.vehicles} activeRoutes={activeRoutes} position={position} onSelectStop={setSelectedStop} /> : <div className="map-loading"><span />Loading live map…</div>}
        <div className="map-status"><span className={overallOk ? 'status-dot live' : 'status-dot unavailable'} />{overallOk ? `${snapshot?.vehicles.length ?? 0} buses on map` : 'Feeds unavailable'}</div>
        <div className="map-key"><span><i className="iu-dot" /> IU</span><span><i className="bt-dot" /> BT</span></div>
      </section>

      <section className="arrival-sheet">
        <div className="sheet-handle" />
        <div className="sheet-heading">
          <div><p className="eyebrow">{selectedStop ? `${selectedStop.agency === 'iu' ? 'IU Campus Bus' : 'Bloomington Transit'} stop` : position ? 'Closest to you' : 'Closest to downtown'}</p><h1>{selectedStop?.name || 'Nearby arrivals'}</h1>{selectedStop && selectedDistance != null && <p className="walk-note">{formatDistance(selectedDistance)} away · ~{Math.max(1, Math.ceil(selectedDistance / 81))} min walk</p>}</div>
          {selectedStop ? <button className={`favorite ${favoriteKeys.has(stopKey(selectedStop)) ? 'saved' : ''}`} type="button" onClick={() => toggleFavorite(selectedStop)} aria-label="Favorite this stop">★</button> : <span className={`live-pill ${overallOk ? '' : 'offline'}`}><i />{overallOk ? 'Live now' : 'Unavailable'}</span>}
        </div>
        {leaveText && <div className={`leave-card ${leaveText === 'Probably too late to walk' ? 'late' : ''}`}><span>Walking estimate</span><strong>{leaveText}</strong></div>}
        <div className="arrival-list">
          {displayArrivals.length ? displayArrivals.map((arrival, index) => {
            const route = routeMap.get(routeKey(arrival.agency, arrival.routeId));
            const stop = snapshot?.stops.find((item) => item.agency === arrival.agency && item.id === arrival.stopId);
            const minutes = Math.max(0, Math.ceil((arrival.predictedArrival - now) / 60_000));
            return <button className="arrival-card" type="button" key={`${arrival.agency}:${arrival.tripId || arrival.vehicleId || index}:${arrival.stopId}`} onClick={() => stop && setSelectedStop(stop)}>
              <span className="route-badge" style={{ backgroundColor: route?.color || (arrival.agency === 'iu' ? '#990000' : '#006298'), color: route?.textColor || '#fff' }}>{route?.shortName || arrival.routeId}</span>
              <span className="arrival-copy"><strong>{selectedStop ? (arrival.destination || route?.longName || 'Direction unavailable') : (stop?.name || 'Nearby stop')}</strong><span>{arrival.agency.toUpperCase()} · {arrival.destination || route?.longName || 'Direction unavailable'}</span></span>
              <span className="arrival-time"><strong>{minutes}</strong><small>min</small><em className={arrival.freshness}>{arrival.freshness}</em></span>
            </button>;
          }) : <div className="empty-state"><strong>No upcoming arrivals found</strong><span>{overallOk ? 'Try another nearby stop or route.' : 'Live feeds are temporarily unavailable. The map will retry automatically.'}</span></div>}
        </div>
        {selectedStop && <button className="back-button" type="button" onClick={() => setSelectedStop(undefined)}>← Back to nearby stops</button>}
        <p className="disclaimer">Independent third-party tracker · Not affiliated with Bloomington Transit or Indiana University · Arrival times may change</p>
      </section>
    </main>
  );
}

function distanceMeters(a: [number, number], b: [number, number]) {
  const radians = (value: number) => value * Math.PI / 180;
  const dLat = radians(b[0] - a[0]); const dLng = radians(b[1] - a[1]);
  const value = Math.sin(dLat / 2) ** 2 + Math.cos(radians(a[0])) * Math.cos(radians(b[0])) * Math.sin(dLng / 2) ** 2;
  return 6_371_000 * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value));
}
function formatDistance(meters: number) { return meters < 160 ? `${Math.round(meters / 10) * 10} m` : `${(meters / 1609.344).toFixed(1)} mi`; }
function getLeaveText(arrival: number, distance: number, now: number) {
  const leaveMinutes = Math.floor((arrival - now - distance / 1.35 * 1000 - 60_000) / 60_000);
  if (leaveMinutes < 0) return 'Probably too late to walk';
  if (leaveMinutes <= 1) return 'Leave now';
  return `Leave in ~${leaveMinutes} min`;
}
