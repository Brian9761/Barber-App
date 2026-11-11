// Izzy Clipz Business on a computer (or a phone): the shop's schedule and checkout
// (Today), its analytics, its products and its settings, signed in with a 6-digit code
// from the iPhone app. /business is sign-in (or Today, once signed in); every page shows
// sign-in in its place while this computer isn't signed in, so the owner lands where he
// meant to go.
//
// The installed app's scope is /business/ (public/business/manifest.webmanifest), and
// /business without the slash is outside it: typed in, or opened from the service worker's
// copy, it becomes /business/ at once, so an app added to the Home Screen from sign-in, or a
// window of the installed app, stays inside its own scope.

import type { ReactElement } from 'react';
import { Navigate, Route, Routes, useLocation } from 'react-router-dom';
import { Frame } from './components/Frame';
import { useBusinessHead } from './hooks';
import { AnalyticsPage } from './pages/AnalyticsPage';
import { NotFound } from './pages/NotFound';
import { ProductsPage } from './pages/ProductsPage';
import { SettingsPage } from './pages/SettingsPage';
import { SignInPage } from './pages/SignInPage';
import { TodayPage } from './pages/TodayPage';
import { useSession } from './session';
import './business.css';

export default function BusinessApp() {
  useBusinessHead();
  const { pathname, search, hash } = useLocation();
  const { session } = useSession();
  const signedIn = session !== null;
  if (pathname === '/business') return <Navigate to={{ pathname: '/business/', search, hash }} replace />;
  const gate = (page: ReactElement) => (signedIn ? page : <SignInPage />);
  return (
    <Frame signedIn={signedIn}>
      <Routes>
        <Route index element={signedIn ? <Navigate to="today" replace /> : <SignInPage />} />
        <Route path="today" element={gate(<TodayPage />)} />
        <Route path="analytics" element={gate(<AnalyticsPage />)} />
        <Route path="products" element={gate(<ProductsPage />)} />
        <Route path="settings" element={gate(<SettingsPage />)} />
        <Route path="*" element={<NotFound signedIn={signedIn} />} />
      </Routes>
    </Frame>
  );
}
