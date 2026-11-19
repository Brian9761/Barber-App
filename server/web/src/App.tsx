import { lazy, Suspense, useState } from 'react';
import { Navigate, Route, Routes, useLocation } from 'react-router-dom';
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

type LegalPageComponent = (typeof import('./legal/LegalPage'))['default'];

/** The legal pages' code once it has loaded. */
let loadedLegalPage: LegalPageComponent | null = null;
let legalPageLoad: Promise<LegalPageComponent> | null = null;

/**
 * The legal pages, with the documents' words: their code, loaded once, when one is opened, or
 * before the site first draws when it opens on one (main.tsx), so the site replaces a policy's
 * plain HTML with the same page in one go, never with "Loading…" in between.
 */
export function loadLegalPage(): Promise<LegalPageComponent> {
  legalPageLoad ??= import('./legal/LegalPage').then(
    (module) => {
      loadedLegalPage = module.default;
      return module.default;
    },
    (error: unknown) => {
      // Asked for again next time (the page's own load, when main.tsx's didn't come).
      legalPageLoad = null;
      throw error;
    },
  );
  return legalPageLoad;
}

const LazyLegalPage = lazy(() => loadLegalPage().then((page) => ({ default: page })));

function Legal({ id }: { id: LegalDocumentId }) {
  // Chosen when the page opens, and kept: once the code is here the page draws at once (a lazy
  // component shows its fallback the first time it's drawn, even when its code is already here),
  // and until then it loads first.
  const [Loaded] = useState(() => loadedLegalPage);
  // Keyed by the document, so each one opened in the site starts as its own page (a policy taken
  // over from its plain HTML keeps that page's state only).
  if (Loaded) return <Loaded key={id} id={id} />;
  return (
    <Suspense
      fallback={
        <div className="container legal-loading">
          <Loading text="Loading…" />
        </div>
      }
    >
      <LazyLegalPage key={id} id={id} />
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
 * The site's page's own file, /index.html: Home, at its own address (the hosting redirects it too,
 * but the service worker opens it from its copy without asking), never "This page isn't here.".
 */
function HomeAddress() {
  const { search, hash } = useLocation();
  return <Navigate to={{ pathname: '/', search, hash }} replace />;
}

/**
 * The site's pages (the legal ones too), all under the global nav and footer, where a page that
 * can't be drawn says so (components/PageError.tsx); and Izzy Clipz Business, under its own.
 */
export function App() {
  return (
    <Routes>
      <Route path="business/*" element={<Business />} />
      <Route path="index.html" element={<HomeAddress />} />
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
