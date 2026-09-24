'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import L from 'leaflet';
import { maplibreGL } from '@maplibre/maplibre-gl-leaflet';
import { setWorkerUrl, type GeoJSONSource } from 'maplibre-gl';
import { Circle, CircleMarker, MapContainer, Marker, Popup, useMap } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import 'maplibre-gl/dist/maplibre-gl.css';
import type { FeatureCollection, LineString, Point } from 'geojson';
import type { TransitRoute, TransitStop, TransitVehicle } from '@/src/transit/types';
import type { TrackedTrip } from '@/src/transit/trip';
import type { LocationFix } from '../hooks/useLiveLocation';
import { PeopleIcon } from './icons';

export type MapFocus = { kind: 'routes' | 'stop' | 'me'; n: number; lat?: number; lng?: number };

type Props = {
  routes: TransitRoute[];
  stops: TransitStop[];
  vehicles: TransitVehicle[];
  activeRoutes: Set<string>;
  favorites: string[];
  selectedStop?: TransitStop;
  trip?: TrackedTrip;
  tripVehicleId?: string;
  position?: LocationFix;
  focus: MapFocus;
  sheetOpen: boolean;
  onSelectStop: (stop: TransitStop) => void;
};

const key = (agency: string, id: string) => `${agency}:${id}`;
const ROUTE_SOURCE_ID = 'selected-transit-routes';
const ROUTE_CASING_ID = 'selected-transit-route-casing';
const ROUTE_LAYER_ID = 'selected-transit-route-lines';
const STOP_SOURCE_ID = 'selected-transit-stops';
const STOP_LAYER_ID = 'selected-transit-stop-points';
const STOP_HIT_ICON = L.divIcon({ className: 'stop-hit-marker', iconSize: [24, 24], iconAnchor: [12, 12], html: '' });
type RouteGeoJson = FeatureCollection<LineString, { color: string }>;
type StopGeoJson = FeatureCollection<Point, { agency: string; id: string; favorite: number }>;

export default function TransitMap({ routes, stops, vehicles, activeRoutes, favorites, selectedStop, trip, tripVehicleId, position, focus, sheetOpen, onSelectStop }: Props) {
  // The tracked route stays visible even if it isn't one of the picked routes.
  const shownRoutes = useMemo(() => {
    const shown = new Set(activeRoutes);
    if (trip) shown.add(key(trip.agency, trip.routeId));
    return shown;
  }, [activeRoutes, trip]);
  const favoriteSet = useMemo(() => new Set(favorites), [favorites]);
  const routeMap = useMemo(() => new Map(routes.map((route) => [key(route.agency, route.id), route])), [routes]);
  const stopMap = useMemo(() => new Map(stops.map((stop) => [key(stop.agency, stop.id), stop])), [stops]);
  const routeData = useMemo<RouteGeoJson>(() => ({
    type: 'FeatureCollection',
    features: routes.filter((route) => shownRoutes.has(key(route.agency, route.id))).flatMap((route) =>
      (route.paths ?? []).map((path) => ({
        type: 'Feature' as const,
        properties: { color: route.color || '#315b50' },
        geometry: { type: 'LineString' as const, coordinates: path.map(([lat, lng]) => [lng, lat]) },
      }))),
  }), [shownRoutes, routes]);
  const visibleStops = useMemo(() => stops.filter((stop) => favoriteSet.has(key(stop.agency, stop.id))
    || stop.routeIds?.some((id) => shownRoutes.has(key(stop.agency, id)))), [favoriteSet, shownRoutes, stops]);
  const stopData = useMemo<StopGeoJson>(() => ({
    type: 'FeatureCollection',
    features: visibleStops.map((stop) => ({
      type: 'Feature' as const,
      properties: { agency: stop.agency, id: stop.id, favorite: favoriteSet.has(key(stop.agency, stop.id)) ? 1 : 0 },
      geometry: { type: 'Point' as const, coordinates: [stop.lng, stop.lat] },
    })),
  }), [favoriteSet, visibleStops]);
  const shown = (agency: string, routeId?: string) => Boolean(routeId && shownRoutes.has(key(agency, routeId)));

  return (
    <MapContainer center={[39.1699, -86.5258]} zoom={14} zoomSnap={.1} scrollWheelZoom className="transit-map" zoomControl={false}>
      <Basemap routeData={routeData} stopData={stopData} />
      <ResizeMap />
      <FocusController routes={routes} shownRoutes={shownRoutes} focus={focus} sheetOpen={sheetOpen} />
      {visibleStops.map((stop) => <Marker key={`stop:${key(stop.agency, stop.id)}`} position={[stop.lat, stop.lng]} icon={STOP_HIT_ICON} title={stop.name} zIndexOffset={-1000} eventHandlers={{ click: () => onSelectStop(stop) }} />)}
      {selectedStop && <Marker position={[selectedStop.lat, selectedStop.lng]} icon={selectedStopIcon(selectedStop.agency)} zIndexOffset={500} interactive={false} />}
      {vehicles.filter((vehicle) => shown(vehicle.agency, vehicle.routeId)).map((vehicle) => {
        const route = vehicle.routeId ? routeMap.get(key(vehicle.agency, vehicle.routeId)) : undefined;
        const tracked = Boolean(trip && vehicle.agency === trip.agency && vehicle.id === tripVehicleId);
        return <Marker key={key(vehicle.agency, vehicle.id)} position={[vehicle.lat, vehicle.lng]} zIndexOffset={tracked ? 1000 : 0} icon={vehicleIcon(route?.shortName.trim() || '•', route?.color, vehicle.agency, vehicle.freshness, vehicle.heading, tracked)}>
          <Popup><VehiclePopup vehicle={vehicle} route={route} stopMap={stopMap} /></Popup>
        </Marker>;
      })}
      {position && <>
        {position.accuracy > 15 && <Circle center={[position.lat, position.lng]} radius={Math.min(position.accuracy, 300)} interactive={false} pathOptions={{ className: 'accuracy-ring', color: '#2f6bff', weight: 1, fillOpacity: .12 }} />}
        <CircleMarker center={[position.lat, position.lng]} radius={8} interactive={false} pathOptions={{ className: 'me-dot', color: '#fff', fillColor: '#2f6bff', fillOpacity: 1, weight: 3 }} />
      </>}
    </MapContainer>
  );
}

function FocusController({ routes, shownRoutes, focus, sheetOpen }: { routes: TransitRoute[]; shownRoutes: Set<string>; focus: MapFocus; sheetOpen: boolean }) {
  const map = useMap();
  const handled = useRef(-1);
  const latest = useRef({ routes, shownRoutes, sheetOpen });
  useEffect(() => { latest.current = { routes, shownRoutes, sheetOpen }; }, [routes, shownRoutes, sheetOpen]);

  useEffect(() => {
    if (handled.current === focus.n) return;
    handled.current = focus.n;
    const { routes: allRoutes, shownRoutes: shownNow, sheetOpen: sheet } = latest.current;
    const mobile = window.innerWidth < 900;
    const bottom = mobile && sheet ? Math.min(window.innerHeight * .6, 520) : 24;
    if (focus.kind === 'routes') {
      const points = allRoutes.filter((route) => shownNow.has(key(route.agency, route.id))).flatMap((route) => route.paths ?? []).flat();
      if (points.length) map.fitBounds(L.latLngBounds(points), { animate: focus.n > 0, maxZoom: 16, paddingTopLeft: [24, 72], paddingBottomRight: [24, bottom] });
      return;
    }
    if (focus.lat == null || focus.lng == null) return;
    const zoom = Math.max(map.getZoom(), 16);
    // Nudge the target up so the sheet doesn't cover it.
    const target = map.project([focus.lat, focus.lng], zoom).add([0, bottom / 2 - 12]);
    map.flyTo(map.unproject(target, zoom), zoom, { duration: .6 });
  }, [focus, map]);
  return null;
}

function ResizeMap() {
  const map = useMap();
  useEffect(() => {
    let frame = 0;
    const resize = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => map.invalidateSize({ pan: false, debounceMoveend: true }));
    };
    const container = map.getContainer();
    const observer = new ResizeObserver(resize);
    observer.observe(container);
    resize();
    return () => { cancelAnimationFrame(frame); observer.disconnect(); };
  }, [map]);
  return null;
}

function usePrefersDark() {
  const [dark, setDark] = useState(() => typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches);
  useEffect(() => {
    const query = window.matchMedia('(prefers-color-scheme: dark)');
    const onChange = () => setDark(query.matches);
    query.addEventListener('change', onChange);
    return () => query.removeEventListener('change', onChange);
  }, []);
  return dark;
}

function Basemap({ routeData, stopData }: { routeData: RouteGeoJson; stopData: StopGeoJson }) {
  const map = useMap();
  const dark = usePrefersDark();
  const layerRef = useRef<L.MaplibreGL | null>(null);
  const routeDataRef = useRef(routeData);
  const stopDataRef = useRef(stopData);

  const darkRef = useRef(dark);
  const styleUrl = (isDark: boolean) => `https://tiles.openfreemap.org/styles/${isDark ? 'dark' : 'positron'}`;

  useEffect(() => {
    setWorkerUrl('/maplibre-gl-worker.mjs');
    const attribution = '<a href="https://openfreemap.org/">OpenFreeMap</a> © <a href="https://openmaptiles.org/">OpenMapTiles</a> Data from <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>';
    const layer = maplibreGL({ style: styleUrl(darkRef.current), attributionControl: false }).addTo(map);
    layerRef.current = layer;
    const glMap = layer.getMaplibreMap();
    // Runs on first load and again after every theme switch replaces the style.
    const installTransitLayers = () => {
      const isDark = darkRef.current;
      if (!glMap.getSource(ROUTE_SOURCE_ID)) glMap.addSource(ROUTE_SOURCE_ID, { type: 'geojson', data: routeDataRef.current });
      if (!glMap.getLayer(ROUTE_CASING_ID)) glMap.addLayer({
        id: ROUTE_CASING_ID, type: 'line', source: ROUTE_SOURCE_ID,
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': isDark ? '#000000' : '#ffffff', 'line-width': 8, 'line-opacity': .85 },
      });
      if (!glMap.getLayer(ROUTE_LAYER_ID)) glMap.addLayer({
        id: ROUTE_LAYER_ID, type: 'line', source: ROUTE_SOURCE_ID,
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': ['get', 'color'], 'line-width': 4.5, 'line-opacity': .9 },
      });
      if (!glMap.getSource(STOP_SOURCE_ID)) glMap.addSource(STOP_SOURCE_ID, { type: 'geojson', data: stopDataRef.current });
      if (!glMap.getLayer(STOP_LAYER_ID)) glMap.addLayer({
        id: STOP_LAYER_ID, type: 'circle', source: STOP_SOURCE_ID,
        paint: {
          'circle-radius': ['interpolate', ['linear'], ['zoom'], 12, ['case', ['==', ['get', 'favorite'], 1], 4, 1.5], 15, ['case', ['==', ['get', 'favorite'], 1], 7, 4.5], 17, ['case', ['==', ['get', 'favorite'], 1], 9, 6.5]],
          'circle-color': ['case', ['==', ['get', 'favorite'], 1], '#ffcb2f', isDark ? '#1f1c17' : '#ffffff'],
          'circle-stroke-color': isDark ? '#fff4de' : '#15130f',
          'circle-stroke-width': ['interpolate', ['linear'], ['zoom'], 12, 1, 15, ['case', ['==', ['get', 'favorite'], 1], 2.5, 2]],
        },
      });
    };
    glMap.on('style.load', installTransitLayers);
    if (glMap.isStyleLoaded()) installTransitLayers();
    map.attributionControl.addAttribution(attribution);

    return () => {
      glMap.off('style.load', installTransitLayers);
      layerRef.current = null;
      map.attributionControl.removeAttribution(attribution);
      map.removeLayer(layer);
    };
  }, [map]);

  // Swap the style in place; recreating the layer on a live Leaflet map breaks it.
  useEffect(() => {
    if (darkRef.current === dark) return;
    darkRef.current = dark;
    layerRef.current?.getMaplibreMap().setStyle(styleUrl(dark));
  }, [dark]);

  useEffect(() => {
    routeDataRef.current = routeData;
    (layerRef.current?.getMaplibreMap().getSource(ROUTE_SOURCE_ID) as GeoJSONSource | undefined)?.setData(routeData);
  }, [routeData]);

  useEffect(() => {
    stopDataRef.current = stopData;
    (layerRef.current?.getMaplibreMap().getSource(STOP_SOURCE_ID) as GeoJSONSource | undefined)?.setData(stopData);
  }, [stopData]);
  return null;
}

function VehiclePopup({ vehicle, route, stopMap }: { vehicle: TransitVehicle; route?: TransitRoute; stopMap: Map<string, TransitStop> }) {
  const occupancy = vehicle.load != null && vehicle.capacity != null
    ? Math.min(100, Math.max(0, (vehicle.load / vehicle.capacity) * 100))
    : undefined;
  const schedule = scheduleStatus(vehicle.onSchedule);

  return <div className="vehicle-popup">
    <div className="vehicle-facts">
      <span className="vehicle-route">{route?.shortName.trim() || 'Bus'} · {vehicle.agency.toUpperCase()}</span>
      <strong className="vehicle-direction">{vehicle.direction || route?.longName || 'Direction unavailable'}</strong>
      <span className="vehicle-fact"><PeopleIcon className="occupancy-icon" />{occupancy == null ? <em>Crowding unavailable</em> : <span className="occupancy-meter" role="progressbar" aria-label="Bus occupancy" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(occupancy)}><i style={{ width: `${occupancy}%` }} /></span>}</span>
      <span className="vehicle-fact"><i className={`schedule-dot ${schedule.state}`} aria-hidden="true" /><strong>{schedule.label}</strong></span>
    </div>
    {vehicle.nextStops?.length ? <div className="vehicle-next-stops"><b>Next stops</b><ol>{vehicle.nextStops.slice(0, 4).map((stop, index) => <li key={`${stop.stopId}:${index}`}><span>{stopMap.get(key(vehicle.agency, stop.stopId))?.name || 'Upcoming stop'}</span><em>{stop.minutes <= 0 ? 'Now' : `${stop.minutes} min`}</em></li>)}</ol></div> : <p className="vehicle-unavailable">Upcoming stops unavailable</p>}
    {vehicle.freshness !== 'live' && <p className="vehicle-unavailable">Position may be out of date</p>}
  </div>;
}

function selectedStopIcon(agency: string) {
  return L.divIcon({ className: '', iconSize: [34, 44], iconAnchor: [17, 42], html: `<div class="stop-pin ${agency}"><span></span></div>` });
}

function vehicleIcon(label: string, routeColor: string | undefined, agency: string, freshness: string, heading: number | undefined, tracked: boolean) {
  const hasHeading = Number.isFinite(heading);
  const rotation = hasHeading ? ((heading! % 360) + 360) % 360 : 0;
  const color = /^#[0-9a-f]{3,8}$/i.test(routeColor || '') ? routeColor : agency === 'iu' ? '#990000' : '#006298';
  return L.divIcon({
    className: '', iconSize: [48, 48], iconAnchor: [24, 24],
    html: `<div class="bus-marker ${agency} ${freshness} ${hasHeading ? 'has-heading' : 'no-heading'} ${tracked ? 'tracked' : ''}" style="--bus-color: ${color}">
      ${hasHeading ? `<span class="bus-arrow" style="transform: rotate(${rotation}deg)"><i></i></span>` : ''}
      <span class="bus-puck"><b>${escapeHtml(label)}</b></span>
    </div>`,
  });
}

function scheduleStatus(value: number | undefined) {
  if (value == null) return { label: 'Schedule unavailable', state: 'unavailable' };
  if (value >= 0) return { label: 'On time', state: 'on-time' };
  return Math.abs(value) <= 5 ? { label: 'Slightly delayed', state: 'slightly-delayed' } : { label: 'Delayed', state: 'delayed' };
}

function escapeHtml(value: string) { return value.replace(/[&<>'"]/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' })[char]!); }
