import type { Metadata, Viewport } from 'next';
import { Geist, Geist_Mono } from 'next/font/google';
import InstallSupport from './components/InstallSupport';
import './globals.css';

const geistSans = Geist({ variable: '--font-geist-sans', subsets: ['latin'] });
const geistMono = Geist_Mono({ variable: '--font-geist-mono', subsets: ['latin'] });

export const metadata: Metadata = {
  metadataBase: new URL('https://btb.singhdan.me'),
  title: 'B-Town Bus — Bloomington + IU Bus Tracker',
  description: 'Live Bloomington Transit and IU Campus Bus arrivals, vehicles, routes, and nearby stops in one independent tracker.',
  applicationName: 'B-Town Bus',
  manifest: '/manifest.webmanifest',
  appleWebApp: {
    capable: true,
    title: 'B-Town Bus',
    statusBarStyle: 'black-translucent',
  },
  icons: {
    icon: [
      { url: '/icon-192.png', sizes: '192x192', type: 'image/png' },
      { url: '/icon-512.png', sizes: '512x512', type: 'image/png' },
    ],
    apple: [{ url: '/apple-touch-icon.png', sizes: '180x180', type: 'image/png' }],
  },
  openGraph: {
    title: 'B-Town Bus',
    description: 'Bloomington + IU buses, live.',
    type: 'website',
    url: '/',
    images: [{ url: '/og.png', width: 1731, height: 909, alt: 'B-Town Bus — Bloomington and IU buses, live' }],
  },
  twitter: {
    card: 'summary_large_image', title: 'B-Town Bus', description: 'Bloomington + IU buses, live.', images: ['/og.png'],
  },
};
export const viewport: Viewport = { width: 'device-width', initialScale: 1, viewportFit: 'cover', themeColor: '#14221e' };

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><head><meta name="apple-mobile-web-app-capable" content="yes" /></head><body className={`${geistSans.variable} ${geistMono.variable}`}><InstallSupport />{children}</body></html>;
}
