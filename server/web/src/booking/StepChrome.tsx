import type { ReactNode } from 'react';
import type { Catalog } from '../api/types';
import { Icon } from '../components/Icon';
import { CallLink } from '../components/ui';
import { usePageMeta } from '../components/usePageMeta';
import { dateTimeLabel } from '../lib/shopTime';
import { useBooking, useStepNavigation } from './BookingContext';
import { summarize } from './describe';
import { STEPS, stepNumber, type Step } from './flow';

/** "Step 2 of 5" over a thin bar, the step's question, a line under it, and Back. */
export function StepHeader({ step, title, subtitle }: { step: Step; title: string; subtitle?: ReactNode }) {
  const { back } = useStepNavigation(step);
  const number = stepNumber(step);
  usePageMeta(`Step ${number} of ${STEPS.length}: ${title}`, 'Book an appointment at Izzy Clipz Barbershop in Oceanside. No payment needed: you pay at the shop.');
  return (
    <div className="step-header">
      <div className="step-header__top">
        <button type="button" className="text-button back-button" onClick={back}>
          <Icon name="chevronLeft" /> Back
        </button>
      </div>
      <div>
        <p className="step-header__count" data-testid="step-count">
          Step {number} of {STEPS.length}
        </p>
        <div className="step-header__bar" aria-hidden="true">
          {STEPS.map((s, i) => (
            <span key={s} className={i < number ? 'is-done' : undefined} />
          ))}
        </div>
      </div>
      <h1 className="step-header__title">{title}</h1>
      {subtitle ? <p className="step-header__subtitle">{subtitle}</p> : null}
    </div>
  );
}

/** The step on the left, "Your appointment" on the right (under it on phones). */
export function BookingLayout({ catalog, children }: { catalog: Catalog; children: ReactNode }) {
  return (
    <div className="booking container container--wide">
      <div className="booking__layout">
        <div className="booking__step">{children}</div>
        <SummaryCard catalog={catalog} />
      </div>
    </div>
  );
}

function SummaryCard({ catalog }: { catalog: Catalog }) {
  const { draft } = useBooking();
  const summary = summarize(catalog, draft);
  const notPicked = <span className="summary-row__empty">Not picked yet</span>;
  return (
    <aside className="summary-card" aria-labelledby="summary-title" data-testid="summary-card">
      <h2 id="summary-title" className="summary-card__title">
        Your appointment
      </h2>
      <dl className="summary-list">
        <div className="summary-row">
          <dt className="summary-row__label">Service</dt>
          <dd className="summary-row__value">{summary.serviceName ?? notPicked}</dd>
        </div>
        <div className="summary-row">
          <dt className="summary-row__label">Barber</dt>
          <dd className="summary-row__value">{summary.barberName ?? notPicked}</dd>
        </div>
        <div className="summary-row">
          <dt className="summary-row__label">Day and time</dt>
          <dd className="summary-row__value">{draft.start ? dateTimeLabel(new Date(draft.start), catalog.timeZone) : notPicked}</dd>
        </div>
        <div className="summary-row">
          <dt className="summary-row__label">Price</dt>
          <dd className="summary-row__value">
            {summary.priceLabel ? (
              <>
                {summary.priceLabel}
                <span className="summary-row__detail"> · {summary.durationLabel}</span>
              </>
            ) : (
              notPicked
            )}
          </dd>
        </div>
      </dl>
      <p className="summary-card__pay">No payment now. You pay at the shop.</p>
      <p className="summary-card__call">
        Prefer to call? <CallLink className="inline-link nowrap" />
      </p>
    </aside>
  );
}
