'use client';

import { useEffect, useState } from 'react';

export default function InstallSupport() {
  const [showIosTip, setShowIosTip] = useState(false);

  useEffect(() => {
    if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(() => undefined);
    const timer = setTimeout(() => {
      const ios = /iphone|ipad|ipod/i.test(navigator.userAgent);
      const standalone = window.matchMedia('(display-mode: standalone)').matches || ('standalone' in navigator && Boolean((navigator as Navigator & { standalone?: boolean }).standalone));
      setShowIosTip(ios && !standalone && localStorage.getItem('btown-ios-install-tip') !== 'dismissed');
    }, 0);
    return () => clearTimeout(timer);
  }, []);

  if (!showIosTip) return null;
  return (
    <aside className="ios-install-tip" role="status">
      <span className="ios-install-icon">B</span>
      <span><strong>Install B-Town Bus</strong><small>Tap Share, then “Add to Home Screen.”</small></span>
      <button type="button" aria-label="Dismiss install instructions" onClick={() => { localStorage.setItem('btown-ios-install-tip', 'dismissed'); setShowIosTip(false); }}>×</button>
    </aside>
  );
}
