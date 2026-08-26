import type { Metadata, Viewport } from 'next';
import { Geist, Geist_Mono } from 'next/font/google';
import './globals.css';

const geistSans = Geist({ variable: '--font-geist-sans', subsets: ['latin'] });
const geistMono = Geist_Mono({ variable: '--font-geist-mono', subsets: ['latin'] });

export const metadata: Metadata = {
  metadataBase: new URL('https://btownbus.singhdan.me'),
  title: 'B-Town Bus — Bloomington + IU Bus Tracker',
  description: 'Live Bloomington Transit and IU Campus Bus arrivals, vehicles, routes, and nearby stops in one independent tracker.',
  applicationName: 'B-Town Bus',
  manifest: '/manifest.webmanifest',
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
export const viewport: Viewport = { width: 'device-width', initialScale: 1, themeColor: '#f4efe4' };

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body className={`${geistSans.variable} ${geistMono.variable}`}>{children}</body></html>;
}
