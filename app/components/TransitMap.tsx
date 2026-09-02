'use client';

import { useEffect, useMemo, useRef } from 'react';
import L from 'leaflet';
import { maplibreGL } from '@maplibre/maplibre-gl-leaflet';
import { setWorkerUrl, type GeoJSONSource } from 'maplibre-gl';
import { CircleMarker, MapContainer, Marker, Popup, useMap } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import 'maplibre-gl/dist/maplibre-gl.css';
import type { FeatureCollection, LineString, Point } from 'geojson';
import type { TransitRoute, TransitStop, TransitVehicle } from '@/src/transit/types';

type Props = {
  routes: TransitRoute[];
  stops: TransitStop[];
  vehicles: TransitVehicle[];
  activeRoutes: Set<string>;
  position?: [number, number];
  sheetCollapsed: boolean;
  recenterRequest: number;
  onViewportChanged: () => void;
  onRecenterComplete: () => void;
  onSelectStop: (stop: TransitStop) => void;
};

const key = (agency: string, id: string) => `${agency}:${id}`;
const ROUTE_SOURCE_ID = 'selected-transit-routes';
const ROUTE_LAYER_ID = 'selected-transit-route-lines';
const STOP_SOURCE_ID = 'selected-transit-stops';
const STOP_LAYER_ID = 'selected-transit-stop-points';
const STOP_HIT_ICON = L.divIcon({ className: 'stop-hit-marker', iconSize: [20, 20], iconAnchor: [10, 10], html: '' });
type RouteGeoJson = FeatureCollection<LineString, { color: string }>;
type StopGeoJson = FeatureCollection<Point, { agency: string; id: string }>;

export default function TransitMap({ routes, stops, vehicles, activeRoutes, position, sheetCollapsed, recenterRequest, onViewportChanged, onRecenterComplete, onSelectStop }: Props) {
  const routeMap = useMemo(() => new Map(routes.map((route) => [key(route.agency, route.id), route])), [routes]);
  const stopMap = useMemo(() => new Map(stops.map((stop) => [key(stop.agency, stop.id), stop])), [stops]);
  const routeData = useMemo<RouteGeoJson>(() => ({
    type: 'FeatureCollection',
    features: routes.filter((route) => activeRoutes.has(key(route.agency, route.id))).flatMap((route) =>
      (route.paths ?? []).map((path) => ({
        type: 'Feature' as const,
        properties: { color: route.color || '#315b50' },
        geometry: { type: 'LineString' as const, coordinates: path.map(([lat, lng]) => [lng, lat]) },
      }))),
  }), [activeRoutes, routes]);
  const selectedStops = useMemo(() => stops
    .filter((stop) => stop.routeIds?.some((id) => activeRoutes.has(key(stop.agency, id)))), [activeRoutes, stops]);
  const stopData = useMemo<StopGeoJson>(() => ({
    type: 'FeatureCollection',
    features: selectedStops.map((stop) => ({
      type: 'Feature' as const,
      properties: { agency: stop.agency, id: stop.id },
      geometry: { type: 'Point' as const, coordinates: [stop.lng, stop.lat] },
    })),
  }), [selectedStops]);
  const visible = (agency: string, routeId?: string) => Boolean(routeId && activeRoutes.has(key(agency, routeId)));
  return (
    <MapContainer center={[39.1699, -86.5258]} zoom={14} scrollWheelZoom className="transit-map" zoomControl={false}>
      <SimpleBasemap routeData={routeData} stopData={stopData} />
      <ResizeMap />
      <RouteViewport routes={routes} activeRoutes={activeRoutes} request={recenterRequest} sheetCollapsed={sheetCollapsed} onViewportChanged={onViewportChanged} onRecenterComplete={onRecenterComplete} />
      <Recenter position={position} />
      {selectedStops.map((stop) => <Marker key={`stop:${key(stop.agency, stop.id)}`} position={[stop.lat, stop.lng]} icon={STOP_HIT_ICON} title={stop.name} zIndexOffset={-1000} eventHandlers={{ click: () => onSelectStop(stop) }} />)}
      {vehicles.filter((vehicle) => visible(vehicle.agency, vehicle.routeId)).map((vehicle) => {
        const route = vehicle.routeId ? routeMap.get(key(vehicle.agency, vehicle.routeId)) : undefined;
        return <Marker key={key(vehicle.agency, vehicle.id)} position={[vehicle.lat, vehicle.lng]} icon={vehicleIcon(route?.shortName || '•', route?.color, vehicle.agency, vehicle.freshness, vehicle.heading)}>
          <Popup><VehiclePopup vehicle={vehicle} stopMap={stopMap} /></Popup>
        </Marker>;
      })}
      {position && <CircleMarker center={position} radius={8} pathOptions={{ color: '#fff', fillColor: '#cf3a26', fillOpacity: 1, weight: 3 }} />}
    </MapContainer>
  );
}

function RouteViewport({ routes, activeRoutes, request, sheetCollapsed, onViewportChanged, onRecenterComplete }: {
  routes: TransitRoute[];
  activeRoutes: Set<string>;
  request: number;
  sheetCollapsed: boolean;
  onViewportChanged: () => void;
  onRecenterComplete: () => void;
}) {
  const map = useMap();
  const fitting = useRef(false);
  const handledRequest = useRef(0);
  const routesRef = useRef(routes);
  const activeRoutesRef = useRef(activeRoutes);
  const sheetCollapsedRef = useRef(sheetCollapsed);

  useEffect(() => { routesRef.current = routes; }, [routes]);
  useEffect(() => { activeRoutesRef.current = activeRoutes; }, [activeRoutes]);
  useEffect(() => { sheetCollapsedRef.current = sheetCollapsed; }, [sheetCollapsed]);

  useEffect(() => {
    const handleMoveStart = () => { if (!fitting.current) onViewportChanged(); };
    map.on('movestart', handleMoveStart);
    return () => { map.off('movestart', handleMoveStart); };
  }, [map, onViewportChanged]);

  useEffect(() => {
    if (request <= 0 || handledRequest.current === request) return;
    handledRequest.current = request;
    const points = routesRef.current
      .filter((route) => activeRoutesRef.current.has(key(route.agency, route.id)))
      .flatMap((route) => route.paths ?? [])
      .flat();
    if (!points.length) {
      onRecenterComplete();
      return;
    }

    fitting.current = true;
    let finished = false;
    const timeout: { value?: ReturnType<typeof setTimeout> } = {};
    const finish = () => {
      if (finished) return;
      finished = true;
      if (timeout.value) clearTimeout(timeout.value);
      map.off('moveend', finish);
      fitting.current = false;
      onRecenterComplete();
    };
    map.once('moveend', finish);
    const bottomPadding = sheetCollapsedRef.current ? 82 : Math.min(window.innerHeight * .58, 570) + 18;
    map.fitBounds(L.latLngBounds(points), {
      animate: true,
      duration: .65,
      maxZoom: 16,
      paddingTopLeft: [18, 18],
      paddingBottomRight: [18, bottomPadding],
    });
    timeout.value = setTimeout(finish, 1100);
    return () => {
      if (timeout.value) clearTimeout(timeout.value);
      map.off('moveend', finish);
      fitting.current = false;
    };
  }, [map, onRecenterComplete, request]);

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

function SimpleBasemap({ routeData, stopData }: { routeData: RouteGeoJson; stopData: StopGeoJson }) {
  const map = useMap();
  const layerRef = useRef<L.MaplibreGL | null>(null);
  const routeDataRef = useRef(routeData);
  const stopDataRef = useRef(stopData);

  useEffect(() => {
    setWorkerUrl('/maplibre-gl-worker.mjs');
    const attribution = '<a href="https://openfreemap.org/">OpenFreeMap</a> © <a href="https://openmaptiles.org/">OpenMapTiles</a> Data from <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>';
    const layer = maplibreGL({
      style: 'https://tiles.openfreemap.org/styles/positron',
      attributionControl: false,
    }).addTo(map);
    layerRef.current = layer;
    const glMap = layer.getMaplibreMap();
    const installTransitLayers = () => {
      if (!glMap.getSource(ROUTE_SOURCE_ID)) glMap.addSource(ROUTE_SOURCE_ID, { type: 'geojson', data: routeDataRef.current });
      if (!glMap.getLayer(ROUTE_LAYER_ID)) glMap.addLayer({
        id: ROUTE_LAYER_ID,
        type: 'line',
        source: ROUTE_SOURCE_ID,
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': ['get', 'color'], 'line-width': 4, 'line-opacity': .72 },
      });
      if (!glMap.getSource(STOP_SOURCE_ID)) glMap.addSource(STOP_SOURCE_ID, { type: 'geojson', data: stopDataRef.current });
      if (!glMap.getLayer(STOP_LAYER_ID)) glMap.addLayer({
        id: STOP_LAYER_ID,
        type: 'circle',
        source: STOP_SOURCE_ID,
        paint: {
          'circle-radius': 4,
          'circle-color': '#fffdf7',
          'circle-stroke-color': ['match', ['get', 'agency'], 'iu', '#990000', '#006298'],
          'circle-stroke-width': 2,
        },
      });
    };
    if (glMap.loaded()) installTransitLayers(); else glMap.on('load', installTransitLayers);
    map.attributionControl.addAttribution(attribution);

    return () => {
      glMap.off('load', installTransitLayers);
      layerRef.current = null;
      map.attributionControl.removeAttribution(attribution);
      map.removeLayer(layer);
    };
  }, [map]);

  useEffect(() => {
    routeDataRef.current = routeData;
    const source = layerRef.current?.getMaplibreMap().getSource(ROUTE_SOURCE_ID) as GeoJSONSource | undefined;
    source?.setData(routeData);
  }, [routeData]);

  useEffect(() => {
    stopDataRef.current = stopData;
    const source = layerRef.current?.getMaplibreMap().getSource(STOP_SOURCE_ID) as GeoJSONSource | undefined;
    source?.setData(stopData);
  }, [stopData]);
  return null;
}

function Recenter({ position }: { position?: [number, number] }) {
  const map = useMap();
  useEffect(() => { if (position) map.flyTo(position, 15, { duration: .7 }); }, [map, position]);
  return null;
}

function VehiclePopup({ vehicle, stopMap }: { vehicle: TransitVehicle; stopMap: Map<string, TransitStop> }) {
  const occupancy = vehicle.load != null && vehicle.capacity != null
    ? Math.min(100, Math.max(0, (vehicle.load / vehicle.capacity) * 100))
    : undefined;
  const schedule = scheduleStatus(vehicle.onSchedule);

  return <div className="vehicle-popup">
    <div className="vehicle-facts">
      <strong className="vehicle-direction">{vehicle.direction || 'Direction unavailable'}</strong>
      <span className="vehicle-fact vehicle-occupancy"><PeopleIcon />{occupancy == null ? <em>Unavailable</em> : <span className="occupancy-meter" role="progressbar" aria-label="Bus occupancy" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(occupancy)}><i style={{ width: `${occupancy}%` }} /></span>}</span>
      <span className="vehicle-fact vehicle-schedule"><i className={`schedule-dot ${schedule.state}`} aria-hidden="true" /><strong>{schedule.label}</strong></span>
    </div>
    {vehicle.nextStops?.length ? <div className="vehicle-next-stops"><b>Next stops</b><ol>{vehicle.nextStops.map((stop, index) => <li key={`${stop.stopId}:${index}`}><span>{stopMap.get(key(vehicle.agency, stop.stopId))?.name || 'Upcoming stop'}</span><em>{formatMinutes(stop.minutes)}</em></li>)}</ol></div> : <p className="vehicle-unavailable">Upcoming stops unavailable</p>}
    {vehicle.freshness !== 'live' && <p className="vehicle-unavailable">Position may be stale</p>}
  </div>;
}

function vehicleIcon(label: string, routeColor: string | undefined, agency: string, freshness: string, heading?: number) {
  const hasHeading = Number.isFinite(heading);
  const rotation = hasHeading ? ((heading! % 360) + 360) % 360 : 0;
  const labelOffset = 2;
  const labelX = -Math.sin(rotation * Math.PI / 180) * labelOffset;
  const labelY = Math.cos(rotation * Math.PI / 180) * labelOffset;
  const color = /^#[0-9a-f]{3,8}$/i.test(routeColor || '') ? routeColor : agency === 'iu' ? '#990000' : '#006298';
  return L.divIcon({
    className: '', iconSize: [46, 46], iconAnchor: [23, 23],
    html: `<div class="bus-marker ${agency} ${freshness} ${hasHeading ? 'has-heading' : 'no-heading'}">
      <span class="bus-body" style="--bus-color: ${color}; transform: rotate(${rotation}deg)"><span class="bus-windshield"></span><span class="bus-headlights"></span></span>
      <b style="transform: translate(${labelX.toFixed(2)}px, ${labelY.toFixed(2)}px)">${escapeHtml(label)}</b>
    </div>`,
  });
}

function PeopleIcon() {
  return <svg className="occupancy-icon" viewBox="0 0 24 24" role="img" aria-label="Occupancy"><circle cx="9" cy="8" r="3" fill="currentColor" /><circle cx="16.5" cy="8.5" r="2.5" fill="currentColor" opacity=".8" /><path d="M3 19c0-3.2 2.7-5.5 6-5.5s6 2.3 6 5.5H3Zm11.5 0c0-1.7-.6-3.1-1.7-4.1 1-.9 2.3-1.4 3.7-1.4 2.5 0 4.5 1.7 4.5 4v1.5h-6.5Z" fill="currentColor" /></svg>;
}

function scheduleStatus(value: number | undefined) {
  if (value == null) return { label: 'Schedule unavailable', state: 'unavailable' };
  if (value >= 0) return { label: 'On time', state: 'on-time' };
  return Math.abs(value) <= 5 ? { label: 'Slightly delayed', state: 'slightly-delayed' } : { label: 'Delayed', state: 'delayed' };
}

function formatMinutes(value: number) { return value <= 0 ? 'Now' : `${value} min`; }

function escapeHtml(value: string) { return value.replace(/[&<>'"]/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' })[char]!); }
