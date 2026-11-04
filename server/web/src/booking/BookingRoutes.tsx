import { useEffect, type ReactNode } from 'react';
import { Navigate, Route, Routes } from 'react-router-dom';
import type { Catalog } from '../api/types';
import { CatalogGate } from '../components/CatalogGate';
import { barberById, offeringById, serviceById } from '../lib/catalog';
import { BarberStep } from './BarberStep';
import { BookingProvider, useBooking } from './BookingContext';
import { CardReturnPage } from './CardReturnPage';
import { ConfirmationPage } from './ConfirmationPage';
import { DetailsStep } from './DetailsStep';
import { canVisit, firstOpenStep, STEP_PATHS, type BookingDraft, type Step } from './flow';
import { ReviewStep } from './ReviewStep';
import { ServiceStep } from './ServiceStep';
import { TimeStep } from './TimeStep';

/** /book and its steps, the confirmation and the way back from Stripe's card page. */
export function BookingRoutes() {
  return (
    <CatalogGate>
      {(catalog) => (
        <BookingProvider>
          <StaleDraftCheck catalog={catalog} />
          <Routes>
            <Route index element={<ServiceStep catalog={catalog} />} />
            <Route path="barber" element={<StepGate step="barber"><BarberStep catalog={catalog} /></StepGate>} />
            <Route path="time" element={<StepGate step="time"><TimeStep catalog={catalog} /></StepGate>} />
            <Route path="details" element={<StepGate step="details"><DetailsStep catalog={catalog} /></StepGate>} />
            <Route path="review" element={<StepGate step="review"><ReviewStep catalog={catalog} /></StepGate>} />
            <Route path="confirmed" element={<ConfirmationPage catalog={catalog} />} />
            <Route path="card-return" element={<CardReturnPage />} />
            <Route path="*" element={<Navigate to="/book" replace />} />
          </Routes>
        </BookingProvider>
      )}
    </CatalogGate>
  );
}

/** A step opens once the ones before it are done; otherwise the first one still to do. */
function StepGate({ step, children }: { step: Step; children: ReactNode }) {
  const { draft } = useBooking();
  if (!canVisit(step, draft)) return <Navigate to={STEP_PATHS[firstOpenStep(draft)]} replace />;
  return <>{children}</>;
}

/** A booking kept from before the menu changed (a service or barber gone): start again. */
function isStale(draft: BookingDraft, catalog: Catalog): boolean {
  if (draft.serviceId && !serviceById(catalog, draft.serviceId)) return true;
  if (draft.barberId && !barberById(catalog, draft.barberId)) return true;
  if (draft.choice?.kind === 'offering' && !offeringById(catalog, draft.choice.offeringId)) return true;
  return false;
}

function StaleDraftCheck({ catalog }: { catalog: Catalog }) {
  const { draft, dispatch } = useBooking();
  const stale = isStale(draft, catalog);
  useEffect(() => {
    if (stale) dispatch({ type: 'begin' });
  }, [stale, dispatch]);
  return null;
}
