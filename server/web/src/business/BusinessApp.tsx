// Izzy Clipz Business on a computer (or a phone): the shop's schedule and checkout
// (Today), its analytics, its products and its settings, signed in with a 6-digit code
// from the iPhone app. /business is sign-in (or Today, once signed in); every page shows
// sign-in in its place while this computer isn't signed in, so the owner lands where he
// meant to go.

import type { ReactElement } from 'react';
import { Navigate, Route, Routes } from 'react-router-dom';
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
  const { session } = useSession();
  const signedIn = session !== null;
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
