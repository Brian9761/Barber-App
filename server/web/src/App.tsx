import { lazy, Suspense } from 'react';
import { Route, Routes, useLocation } from 'react-router-dom';
import { BookingRoutes } from './booking/BookingRoutes';
import { BusinessLoadFailed, BusinessLoading } from './business/BusinessLoading';
import { Layout } from './components/Layout';
import { PageErrorBoundary } from './components/PageError';
import { Loading } from './components/ui';
import { LEGAL_DOCUMENTS, type LegalDocumentId } from './legal/documents';
import { AppointmentsPage } from './pages/AppointmentsPage';
import { BarbersPage } from './pages/BarbersPage';
import { GetTheAppPage } from './pages/GetTheAppPage';
import { HomePage } from './pages/HomePage';
import { NotFoundPage } from './pages/NotFoundPage';
import { ReviewsPage } from './pages/ReviewsPage';
import { ServicesPage } from './pages/ServicesPage';
import { VisitPage } from './pages/VisitPage';

/**
 * Izzy Clipz Business (/business/…): the shop's own area, with its own layout. Its code loads
 * only when it's opened, so the clients' pages never carry it.
 */
const BusinessApp = lazy(() => import('./business/BusinessApp'));

/** The legal pages, with the documents' words: loaded only when one is opened. */
const LegalPage = lazy(() => import('./legal/LegalPage'));

function Legal({ id }: { id: LegalDocumentId }) {
  return (
    <Suspense
      fallback={
        <div className="container legal-loading">
          <Loading text="Loading…" />
        </div>
      }
    >
      <LegalPage id={id} />
    </Suspense>
  );
}

/**
 * React Router's future flags, set so it doesn't warn. Navigation stays outside
 * React transitions: when booking ends a step (booked, or the time was taken), the
 * booking's change and the move to the next page have to show in the same render,
 * or the step's gate sends the client back to the start first.
 */
export const ROUTER_FUTURE = { v7_startTransition: false, v7_relativeSplatPath: true } as const;

/** Izzy Clipz Business, once its code has loaded; and if it couldn't be downloaded, a page that says so. */
function Business() {
  const { pathname } = useLocation();
  return (
    <PageErrorBoundary resetKey={pathname} fallback={(retry) => <BusinessLoadFailed onRetry={retry} />}>
      <Suspense fallback={<BusinessLoading />}>
        <BusinessApp />
      </Suspense>
    </PageErrorBoundary>
  );
}

/**
 * The site's pages (the legal ones too), all under the global nav and footer, where a page that
 * can't be drawn says so (components/PageError.tsx); and Izzy Clipz Business, under its own.
 */
export function App() {
  return (
    <Routes>
      <Route path="business/*" element={<Business />} />
      <Route element={<Layout />}>
        <Route index element={<HomePage />} />
        <Route path="services" element={<ServicesPage />} />
        <Route path="barbers" element={<BarbersPage />} />
        <Route path="reviews" element={<ReviewsPage />} />
        <Route path="visit" element={<VisitPage />} />
        <Route path="book/*" element={<BookingRoutes />} />
        <Route path="appointments" element={<AppointmentsPage />} />
        <Route path="app" element={<GetTheAppPage />} />
        {LEGAL_DOCUMENTS.map((document) => (
          <Route key={document.id} path={document.id} element={<Legal id={document.id} />} />
        ))}
        <Route path="*" element={<NotFoundPage />} />
      </Route>
    </Routes>
  );
}
