'use client';

import { useEffect, useState } from 'react';

type InstallPromptEvent = Event & {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
};

export default function InstallSupport() {
  const [showIosTip, setShowIosTip] = useState(false);
  const [installPrompt, setInstallPrompt] = useState<InstallPromptEvent>();

  useEffect(() => {
    if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(() => undefined);
    const onInstallAvailable = (event: Event) => {
      event.preventDefault();
      if (localStorage.getItem('btown-install-tip') !== 'dismissed') setInstallPrompt(event as InstallPromptEvent);
    };
    const onInstalled = () => setInstallPrompt(undefined);
    window.addEventListener('beforeinstallprompt', onInstallAvailable);
    window.addEventListener('appinstalled', onInstalled);
    const timer = setTimeout(() => {
      const ios = /iphone|ipad|ipod/i.test(navigator.userAgent);
      const standalone = window.matchMedia('(display-mode: standalone)').matches || ('standalone' in navigator && Boolean((navigator as Navigator & { standalone?: boolean }).standalone));
      setShowIosTip(ios && !standalone && localStorage.getItem('btown-ios-install-tip') !== 'dismissed');
    }, 0);
    return () => {
      clearTimeout(timer);
      window.removeEventListener('beforeinstallprompt', onInstallAvailable);
      window.removeEventListener('appinstalled', onInstalled);
    };
  }, []);

  if (installPrompt) return (
    <aside className="ios-install-tip" role="status">
      <span className="ios-install-icon">B</span>
      <span><strong>Install B-Town Bus</strong><small>Add it to your home screen and open it like an app.</small></span>
      <span className="install-actions">
        <button className="install-now" type="button" onClick={async () => { try { await installPrompt.prompt(); await installPrompt.userChoice; } finally { setInstallPrompt(undefined); } }}>Install</button>
        <button type="button" aria-label="Dismiss install instructions" onClick={() => { localStorage.setItem('btown-install-tip', 'dismissed'); setInstallPrompt(undefined); }}>×</button>
      </span>
    </aside>
  );

  if (!showIosTip) return null;
  return (
    <aside className="ios-install-tip" role="status">
      <span className="ios-install-icon">B</span>
      <span><strong>Install B-Town Bus</strong><small>Tap Share, then “Add to Home Screen.”</small></span>
      <button type="button" aria-label="Dismiss install instructions" onClick={() => { localStorage.setItem('btown-ios-install-tip', 'dismissed'); setShowIosTip(false); }}>×</button>
    </aside>
  );
}
