'use client';

import dynamic from 'next/dynamic';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { realtimeFreshness } from '@/src/transit/freshness';
import { startPolling } from '@/src/transit/polling';
import { getClientArrivals, getClientSnapshot } from '@/src/transit/client';
import { distanceMeters, isAtStop, resolveTrip, walkSeconds, type LatLng, type TrackedTrip } from '@/src/transit/trip';
import type { AgencyId, TransitArrival, TransitRoute, TransitSnapshot, TransitStop } from '@/src/transit/types';
import { useLiveLocation } from './hooks/useLiveLocation';
import { arrivalsForStop, routeKey, stopKey } from './lib/ui';
import type { MapFocus } from './components/TransitMap';
import StopCard from './components/StopCard';
import StopSheet from './components/StopSheet';
import TripCard from './components/TripCard';
import RoutePicker from './components/RoutePicker';
import { FitIcon, LocateIcon, MapIcon, NearbyIcon, RouteIcon, StarIcon } from './components/icons';

const TransitMap = dynamic(() => import('./components/TransitMap'), { ssr: false, loading: () => <div className="map-loading"><span />Loading live map…</div> });
const DOWNTOWN: LatLng = [39.1699, -86.5258];
const ROUTES_KEY = 'btown-bus-route-preferences-v1';
const FAVORITES_KEY = 'btown-bus-favorites';
const TAB_KEY = 'btown-bus-tab';
const TRIP_KEY = 'btown-bus-trip';
const TRIP_MAX_AGE = 3 * 60 * 60_000;
type Tab = 'saved' | 'nearby' | 'map';

function readJson<T>(key: string, fallback: T): T {
  try { const raw = localStorage.getItem(key); return raw == null ? fallback : JSON.parse(raw) as T; } catch { return fallback; }
}
function writeJson(key: string, value: unknown) {
  try { if (value === undefined) localStorage.removeItem(key); else localStorage.setItem(key, JSON.stringify(value)); } catch { /* storage may be unavailable in private browsing */ }
}

export default function Home() {
  const [snapshot, setSnapshot] = useState<TransitSnapshot>();
  const [arrivals, setArrivals] = useState<TransitArrival[]>([]);
  const [arrivalsLoadedKey, setArrivalsLoadedKey] = useState('');
  const [ready, setReady] = useState(false);
  const [activeRoutes, setActiveRoutes] = useState<Set<string>>(new Set());
  const [favorites, setFavorites] = useState<string[]>([]);
  const [tab, setTab] = useState<Tab>('nearby');
  const [selectedKey, setSelectedKey] = useState<string>();
  const [routesOpen, setRoutesOpen] = useState(false);
  const [trip, setTrip] = useState<TrackedTrip>();
  const [focus, setFocus] = useState<MapFocus>({ kind: 'routes', n: 0 });
  const [now, setNow] = useState(() => Date.now());
  const location = useLiveLocation();

  // Restore saved preferences once on the client.
  useEffect(() => {
    const timer = setTimeout(() => {
      const routes = readJson<unknown>(ROUTES_KEY, null);
      const savedFavorites = readJson<unknown>(FAVORITES_KEY, []);
      const savedTrip = readJson<TrackedTrip | null>(TRIP_KEY, null);
      const favoriteList = Array.isArray(savedFavorites) ? savedFavorites.filter((item): item is string => typeof item === 'string') : [];
      if (Array.isArray(routes)) setActiveRoutes(new Set(routes.filter((item): item is string => typeof item === 'string')));
      else setRoutesOpen(true);
      setFavorites(favoriteList);
      const savedTab = readJson<Tab | null>(TAB_KEY, null);
      setTab(savedTab === 'map' || savedTab === 'nearby' || savedTab === 'saved' ? savedTab : favoriteList.length ? 'saved' : 'nearby');
      if (savedTrip && Date.now() - savedTrip.startedAt < TRIP_MAX_AGE) setTrip(savedTrip);
      setReady(true);
    }, 0);
    const clock = setInterval(() => {
      const current = Date.now();
      setNow(current);
      // Forget trips left running for hours.
      setTrip((value) => { if (value && current - value.startedAt > TRIP_MAX_AGE) { writeJson(TRIP_KEY, undefined); return undefined; } return value; });
    }, 10_000);
    return () => { clearTimeout(timer); clearInterval(clock); };
  }, []);

  useEffect(() => {
    if (!ready) return;
    return startPolling(async (signal) => {
      const next = await getClientSnapshot();
      if (!signal.aborted) setSnapshot(next);
      // Keep the healthy provider updating normally during a partial outage.
      return next.sources.some((source) => source.ok);
    }, { interval: 15_000, isVisible: () => !document.hidden });
  }, [ready]);

  const stops = useMemo(() => snapshot?.stops ?? [], [snapshot?.stops]);
  const stopMap = useMemo(() => new Map(stops.map((stop) => [stopKey(stop), stop])), [stops]);
  const routeMap = useMemo(() => new Map((snapshot?.routes ?? []).map((route) => [routeKey(route.agency, route.id), route])), [snapshot?.routes]);
  const vehicles = useMemo(() => (snapshot?.vehicles ?? []).map((vehicle) => ({ ...vehicle, freshness: realtimeFreshness(vehicle.updatedAt, now) })), [snapshot?.vehicles, now]);

  const fix = location.fix;
  const hasPosition = Boolean(fix);
  const origin: LatLng = fix ? [fix.lat, fix.lng] : DOWNTOWN;
  const [originLat, originLng] = origin;
  const distanceTo = useCallback((stop: TransitStop) => distanceMeters([originLat, originLng], [stop.lat, stop.lng]), [originLat, originLng]);
  const atStop = (stop: TransitStop) => Boolean(fix && location.isFresh && isAtStop(distanceTo(stop), fix.accuracy));

  const nearbyStops = useMemo(() => {
    const pool = activeRoutes.size ? stops.filter((stop) => stop.routeIds?.some((id) => activeRoutes.has(routeKey(stop.agency, id)))) : stops;
    return pool.map((stop) => ({ stop, distance: distanceTo(stop) })).sort((a, b) => a.distance - b.distance).slice(0, 8);
  }, [activeRoutes, distanceTo, stops]);
  const favoriteStops = useMemo(() => favorites.map((key) => stopMap.get(key)).filter((stop): stop is TransitStop => Boolean(stop)), [favorites, stopMap]);
  const selectedStop = selectedKey ? stopMap.get(selectedKey) : undefined;
  const tripStop = trip ? stopMap.get(`${trip.agency}:${trip.stopId}`) : undefined;

  // One arrivals poll covers everything on screen: the open stop, the trip, saved stops, and nearby stops.
  const requestKey = useMemo(() => {
    const wanted = new Map<string, { agency: AgencyId; id: string }>();
    const add = (stop?: TransitStop) => { if (stop && wanted.size < 24) wanted.set(stopKey(stop), { agency: stop.agency, id: stop.id }); };
    add(selectedStop); add(tripStop);
    favoriteStops.forEach(add);
    nearbyStops.forEach((item) => add(item.stop));
    return JSON.stringify([...wanted.values()].sort((a, b) => stopKey(a).localeCompare(stopKey(b))));
  }, [favoriteStops, nearbyStops, selectedStop, tripStop]);
  useEffect(() => {
    const wanted: { agency: AgencyId; id: string }[] = JSON.parse(requestKey);
    if (!wanted.length) return;
    return startPolling(async (signal) => {
      const next = await getClientArrivals(wanted);
      if (signal.aborted) return;
      setArrivals(next);
      setArrivalsLoadedKey(requestKey);
    }, { interval: 20_000, isVisible: () => !document.hidden });
  }, [requestKey]);
  const arrivalsLoading = arrivalsLoadedKey !== requestKey;

  const tripRoute = trip ? routeMap.get(routeKey(trip.agency, trip.routeId)) : undefined;
  const tripStatus = trip ? resolveTrip(trip, arrivals, snapshot?.vehicles ?? [], tripRoute, now) : undefined;
  const walkMsTo = (stop: TransitStop) => hasPosition ? walkSeconds(distanceTo(stop)) * 1000 : undefined;

  const changeTab = (next: Tab) => { setTab(next); writeJson(TAB_KEY, next); if (next !== 'map') setSelectedKey((key) => tab === 'map' ? undefined : key); };
  const openStop = (stop: TransitStop) => setSelectedKey(stopKey(stop));
  const updateRoutes = (update: (current: Set<string>) => Set<string>) => setActiveRoutes((current) => { const next = update(new Set(current)); writeJson(ROUTES_KEY, [...next]); return next; });
  const toggleRoute = (route: TransitRoute) => updateRoutes((next) => { const item = routeKey(route.agency, route.id); if (next.has(item)) next.delete(item); else next.add(item); return next; });
  const setAgency = (agency: AgencyId, on: boolean) => updateRoutes((next) => { (snapshot?.routes ?? []).filter((route) => route.agency === agency).forEach((route) => { const item = routeKey(route.agency, route.id); if (on) next.add(item); else next.delete(item); }); return next; });
  const toggleFavorite = (stop: TransitStop) => setFavorites((current) => {
    const item = stopKey(stop);
    const next = current.includes(item) ? current.filter((key) => key !== item) : [...current, item];
    writeJson(FAVORITES_KEY, next);
    return next;
  });
  const startTrip = (arrival: TransitArrival) => {
    const same = trip && trip.agency === arrival.agency && trip.stopId === arrival.stopId && trip.routeId === arrival.routeId && trip.vehicleId === arrival.vehicleId;
    const next = same ? undefined : { agency: arrival.agency, routeId: arrival.routeId, stopId: arrival.stopId, vehicleId: arrival.vehicleId, startedAt: Date.now() };
    setTrip(next); writeJson(TRIP_KEY, next);
    if (next && !hasPosition) location.enable();
  };
  const endTrip = () => { setTrip(undefined); writeJson(TRIP_KEY, undefined); };
  const showOnMap = (stop: TransitStop) => { changeTab('map'); setSelectedKey(stopKey(stop)); setFocus((current) => ({ kind: 'stop', lat: stop.lat, lng: stop.lng, n: current.n + 1 })); };
  const locateMe = () => {
    if (location.status === 'off' || location.status === 'denied') location.enable();
    if (fix) setFocus((current) => ({ kind: 'me', lat: fix.lat, lng: fix.lng, n: current.n + 1 }));
  };

  const overallOk = snapshot?.sources.some((source) => source.ok);
  const failedAgencies = snapshot?.sources.filter((source) => !source.ok).map((source) => source.agency.toUpperCase()) ?? [];
  const busCount = vehicles.filter((vehicle) => vehicle.routeId && activeRoutes.has(routeKey(vehicle.agency, vehicle.routeId))).length;
  const handleMapStop = useCallback((stop: TransitStop) => {
    setSelectedKey(stopKey(stop));
    setFocus((current) => ({ kind: 'stop', lat: stop.lat, lng: stop.lng, n: current.n + 1 }));
  }, []);

  const renderStopCard = (stop: TransitStop, distance?: number) => (
    <StopCard key={stopKey(stop)} stop={stop} arrivals={arrivalsForStop(arrivals, stop)} routeMap={routeMap} now={now}
      distance={hasPosition ? distance ?? distanceTo(stop) : undefined} atStop={atStop(stop)} loading={arrivalsLoading}
      favorite={favorites.includes(stopKey(stop))} onOpen={() => openStop(stop)} onToggleFavorite={() => toggleFavorite(stop)} />
  );

  return (
    <div className={`app tab-${tab} ${selectedStop ? 'has-sheet' : ''} ${trip ? 'has-trip' : ''}`}>
      <header className="topbar">
        <a className="brand" href="#" onClick={(event) => { event.preventDefault(); setSelectedKey(undefined); }} aria-label="B-Town Bus home">
          <span className="brand-mark" aria-hidden="true"><span>B</span></span>
          <span className="brand-name"><strong>B-Town</strong><strong>Bus</strong></span>
        </a>
        <div className="topbar-actions">
          <LocationChip status={location.status} onEnable={location.enable} />
          <button className="routes-button" type="button" onClick={() => setRoutesOpen(true)}><RouteIcon />Routes<b>{activeRoutes.size}</b></button>
        </div>
      </header>

      <main className="stage">
        <section className="panel" aria-label={tab === 'saved' ? 'Saved stops' : 'Nearby stops'}>
          <div className="desk-tabs" role="tablist">
            <button role="tab" aria-selected={tab !== 'nearby'} type="button" onClick={() => changeTab('saved')}><StarIcon filled={tab !== 'nearby'} />Saved</button>
            <button role="tab" aria-selected={tab === 'nearby'} type="button" onClick={() => changeTab('nearby')}><NearbyIcon />Nearby</button>
          </div>

          {snapshot && !overallOk && <div className="banner warn">Live feeds are down right now. Retrying automatically.</div>}
          {snapshot && overallOk && failedAgencies.length > 0 && <div className="banner warn">{failedAgencies.join(' & ')} feed is down. Other times are live.</div>}

          {tab !== 'nearby' ? <div className="list-view">
            <div className="view-title"><h1>Saved stops</h1><span>{favoriteStops.length || ''}</span></div>
            {favoriteStops.length ? <div className="card-stack">{favoriteStops.map((stop) => renderStopCard(stop))}</div>
              : <div className="empty-card">
                <StarIcon filled />
                <strong>Star the stops you use</strong>
                <p>Tap the star on any stop and it lands here with live times — one tap from opening the app.</p>
                <button className="primary-button" type="button" onClick={() => changeTab('nearby')}>Find stops nearby</button>
              </div>}
          </div> : <div className="list-view">
            <div className="view-title"><h1>{hasPosition ? 'Near you' : 'Near downtown'}</h1><span>{activeRoutes.size ? 'Your routes' : 'All routes'}</span></div>
            {!hasPosition && location.status !== 'locating' && <button className="banner action" type="button" onClick={location.enable}><LocateIcon />{location.status === 'denied' ? 'Location is blocked. Allow it for this site in Settings, then tap here.' : 'Turn on location to see stops around you'}</button>}
            {location.status === 'locating' && !hasPosition && <div className="banner">Finding you…</div>}
            {nearbyStops.length ? <div className="card-stack">{nearbyStops.map(({ stop, distance }) => renderStopCard(stop, distance))}</div>
              : <div className="empty-card"><strong>{snapshot ? 'No stops found' : 'Loading stops…'}</strong></div>}
          </div>}
          <p className="fine-print">Independent tracker · Not affiliated with Bloomington Transit or Indiana University.</p>
        </section>

        <section className="map-pane" aria-label="Live map">
          {snapshot ? <TransitMap routes={snapshot.routes} stops={snapshot.stops} vehicles={vehicles} activeRoutes={activeRoutes}
            favorites={favorites} selectedStop={selectedStop} trip={trip} tripVehicleId={tripStatus?.vehicle?.id}
            position={fix} focus={focus} sheetOpen={Boolean(selectedStop)} onSelectStop={handleMapStop} />
            : <div className="map-loading"><span />Loading live map…</div>}
          <div className="map-status"><i className={overallOk ? 'live' : snapshot ? 'down' : ''} />{!snapshot ? 'Connecting…' : overallOk ? activeRoutes.size ? busCount ? `${busCount} ${busCount === 1 ? 'bus' : 'buses'} live` : 'No buses running' : 'Pick routes to see buses' : 'Feeds unavailable'}</div>
          <div className="map-buttons">
            <button type="button" onClick={() => setFocus((current) => ({ kind: 'routes', n: current.n + 1 }))} disabled={!activeRoutes.size} aria-label="Fit my routes"><FitIcon /></button>
            <button type="button" onClick={locateMe} aria-label="Show my location" className={location.status === 'live' ? 'on' : ''}><LocateIcon /></button>
          </div>
        </section>

        {selectedStop && <StopSheet stop={selectedStop} arrivals={arrivalsForStop(arrivals, selectedStop)} routeMap={routeMap} vehicles={vehicles} now={now}
          distance={hasPosition ? distanceTo(selectedStop) : undefined} walkMs={walkMsTo(selectedStop)} atStop={atStop(selectedStop)}
          locationStatus={location.status} favorite={favorites.includes(stopKey(selectedStop))} trip={trip} overMap={tab === 'map'}
          loading={arrivalsLoading} onClose={() => setSelectedKey(undefined)} onToggleFavorite={() => toggleFavorite(selectedStop)} onTrack={startTrip}
          onShowMap={() => showOnMap(selectedStop)} onEnableLocation={location.enable} />}

        {trip && tripStatus && !(selectedStop && tab !== 'map') && <TripCard trip={trip} status={tripStatus} route={tripRoute} stop={tripStop}
          walkMs={tripStop ? walkMsTo(tripStop) : undefined} atStop={tripStop ? atStop(tripStop) : false} now={now}
          onOpen={() => tripStop && openStop(tripStop)} onEnd={endTrip} />}
      </main>

      <nav className="tabbar" aria-label="Views">
        <button type="button" aria-current={tab === 'saved'} onClick={() => changeTab('saved')}><StarIcon filled={tab === 'saved'} /><span>Saved</span></button>
        <button type="button" aria-current={tab === 'nearby'} onClick={() => changeTab('nearby')}><NearbyIcon /><span>Nearby</span></button>
        <button type="button" aria-current={tab === 'map'} onClick={() => changeTab('map')}><MapIcon /><span>Map</span></button>
      </nav>

      {routesOpen && snapshot && <RoutePicker routes={snapshot.routes} active={activeRoutes} onToggle={toggleRoute} onSetAgency={setAgency}
        onClose={() => { setRoutesOpen(false); setFocus((current) => ({ kind: 'routes', n: current.n + 1 })); }} />}
    </div>
  );
}

function LocationChip({ status, onEnable }: { status: ReturnType<typeof useLiveLocation>['status']; onEnable: () => void }) {
  if (status === 'live') return <span className="loc-chip live" title="Location is live"><i />GPS</span>;
  if (status === 'locating' || status === 'stale') return <span className="loc-chip wait" title="Updating location"><i />GPS</span>;
  return <button className="loc-chip off" type="button" onClick={onEnable} title={status === 'denied' ? 'Location blocked in Settings' : 'Turn on location'}><LocateIcon />{status === 'denied' ? 'Blocked' : 'Locate'}</button>;
}
