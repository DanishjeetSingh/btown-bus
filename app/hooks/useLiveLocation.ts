'use client';

import { useCallback, useEffect, useRef, useState } from 'react';

export type LocationFix = { lat: number; lng: number; accuracy: number; timestamp: number };
export type LocationStatus = 'off' | 'locating' | 'live' | 'stale' | 'denied' | 'unavailable';

const ENABLED_KEY = 'btown-bus-location-enabled';
const LAST_FIX_KEY = 'btown-bus-last-fix';
/** Without a new fix for this long, the watch is kicked for a fresh one. */
const REFRESH_AFTER_MS = 45_000;
/** A standing-still phone may not report for a while; only call it stale after this. */
export const STALE_AFTER_MS = 120_000;
/** Don't restart a watch more often than this, so a slow GPS isn't interrupted. */
const RESTART_COOLDOWN_MS = 20_000;
const RESUME_GRACE_MS = 4_000;
/** The saved position is only reused on launch if it's this recent. */
const RESTORE_MAX_AGE_MS = 10 * 60_000;

/**
 * One long-lived `watchPosition` for the whole page, never repeated
 * `getCurrentPosition` calls. iOS home-screen apps show the permission sheet
 * for each new request, so the old tap-to-locate flow asked over and over.
 * The watch is only restarted when fixes stop arriving (iOS pauses
 * watches while the app is in the background, which is what made the
 * location go stale).
 */
export function useLiveLocation() {
  const [fix, setFix] = useState<LocationFix>();
  const [status, setStatus] = useState<LocationStatus>('off');
  const [now, setNow] = useState(() => Date.now());
  const watchId = useRef<number | undefined>(undefined);
  const startedAt = useRef(0);
  const lastFixAt = useRef(0);
  const resumedAt = useRef(0);

  const stopWatch = () => {
    if (watchId.current != null) navigator.geolocation.clearWatch(watchId.current);
    watchId.current = undefined;
  };

  const startWatch = useCallback(() => {
    if (!('geolocation' in navigator)) { setStatus('unavailable'); return; }
    stopWatch();
    startedAt.current = Date.now();
    setStatus((current) => current === 'live' || current === 'stale' ? current : 'locating');
    watchId.current = navigator.geolocation.watchPosition(({ coords, timestamp }) => {
      const next = { lat: coords.latitude, lng: coords.longitude, accuracy: coords.accuracy, timestamp: Math.min(timestamp || Date.now(), Date.now()) };
      lastFixAt.current = Date.now();
      setFix(next);
      setStatus('live');
      try { localStorage.setItem(LAST_FIX_KEY, JSON.stringify(next)); } catch { /* storage may be unavailable */ }
    }, (error) => {
      if (error.code === error.PERMISSION_DENIED) {
        stopWatch();
        setStatus('denied');
        try { localStorage.removeItem(ENABLED_KEY); } catch { /* storage may be unavailable */ }
      }
      // Timeouts and unavailable fixes keep the watch alive; the stale check handles recovery.
    }, { enableHighAccuracy: true, maximumAge: 5_000, timeout: 30_000 });
  }, []);

  const enable = useCallback(() => {
    try { localStorage.setItem(ENABLED_KEY, '1'); } catch { /* storage may be unavailable */ }
    if (watchId.current == null) startWatch();
  }, [startWatch]);

  const disable = useCallback(() => {
    try { localStorage.removeItem(ENABLED_KEY); } catch { /* storage may be unavailable */ }
    stopWatch();
    setStatus('off');
  }, []);

  // Resume automatically when the user turned location on before, or the browser already granted it.
  useEffect(() => {
    let cancelled = false;
    const timer = setTimeout(async () => {
      let enabled = false;
      let saved: LocationFix | null = null;
      try {
        enabled = localStorage.getItem(ENABLED_KEY) === '1';
        saved = JSON.parse(localStorage.getItem(LAST_FIX_KEY) || 'null') as LocationFix | null;
      } catch { /* ignore damaged local preference */ }
      let granted = false;
      try { granted = (await navigator.permissions?.query({ name: 'geolocation' }))?.state === 'granted'; } catch { /* Permissions API is optional */ }
      if (cancelled || !(enabled || granted)) return;
      // Show the last spot briefly while the first live fix arrives; it's marked stale, so it never counts as "at the stop".
      if (saved && Date.now() - saved.timestamp < RESTORE_MAX_AGE_MS) { setFix(saved); setStatus('stale'); }
      startWatch();
    }, 0);
    return () => { cancelled = true; clearTimeout(timer); stopWatch(); };
  }, [startWatch]);

  // Kick the watch when fixes stop arriving. After returning to the front, give the
  // paused watch a few seconds to deliver before replacing it.
  useEffect(() => {
    let resumeTimer: ReturnType<typeof setTimeout> | undefined;
    const check = () => {
      const current = Date.now();
      setNow(current);
      if (watchId.current == null || document.hidden) return;
      const age = current - (lastFixAt.current || startedAt.current);
      if (age <= REFRESH_AFTER_MS) return;
      if (age > STALE_AFTER_MS) setStatus((value) => value === 'live' ? 'stale' : value);
      if (current - startedAt.current > RESTART_COOLDOWN_MS && current - resumedAt.current >= RESUME_GRACE_MS) startWatch();
    };
    const onVisible = () => {
      if (document.hidden) return;
      resumedAt.current = Date.now();
      setNow(resumedAt.current);
      clearTimeout(resumeTimer);
      resumeTimer = setTimeout(check, RESUME_GRACE_MS);
    };
    const interval = setInterval(check, 5_000);
    document.addEventListener('visibilitychange', onVisible);
    window.addEventListener('pageshow', onVisible);
    return () => { clearInterval(interval); clearTimeout(resumeTimer); document.removeEventListener('visibilitychange', onVisible); window.removeEventListener('pageshow', onVisible); };
  }, [startWatch]);

  const age = fix ? now - fix.timestamp : undefined;
  return { fix, status, age, isFresh: status === 'live' && age != null && age <= STALE_AFTER_MS, enable, disable };
}
