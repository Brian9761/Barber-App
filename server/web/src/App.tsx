import { Route, Routes } from 'react-router-dom';
import { Layout } from './components/Layout';
import { BarbersPage } from './pages/BarbersPage';
import { BusinessPage } from './pages/BusinessPage';
import { HomePage } from './pages/HomePage';
import { NotFoundPage } from './pages/NotFoundPage';
import { ReviewsPage } from './pages/ReviewsPage';
import { ServicesPage } from './pages/ServicesPage';
import { VisitPage } from './pages/VisitPage';

/**
 * React Router's future flags, set so it doesn't warn. Navigation stays outside
 * React transitions: when booking ends a step (booked, or the time was taken), the
 * booking's change and the move to the next page have to show in the same render,
 * or the step's gate sends the client back to the start first.
 */
export const ROUTER_FUTURE = { v7_startTransition: false, v7_relativeSplatPath: true } as const;

/** The site's pages, all under the global nav and footer. */
export function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<HomePage />} />
        <Route path="services" element={<ServicesPage />} />
        <Route path="barbers" element={<BarbersPage />} />
        <Route path="reviews" element={<ReviewsPage />} />
        <Route path="visit" element={<VisitPage />} />
        <Route path="business/*" element={<BusinessPage />} />
        <Route path="*" element={<NotFoundPage />} />
      </Route>
    </Routes>
  );
}
