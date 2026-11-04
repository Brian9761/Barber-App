import { Route, Routes } from 'react-router-dom';
import { Layout } from './components/Layout';
import { NotFoundPage } from './pages/NotFoundPage';

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
        <Route path="*" element={<NotFoundPage />} />
      </Route>
    </Routes>
  );
}
