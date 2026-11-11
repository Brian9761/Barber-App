import { useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import type { Catalog, CatalogService, Offering } from '../api/types';
import { Icon } from '../components/Icon';
import { Monogram } from '../components/ui';
import { barberById, categories, monogramTone, offeringsForBarber, serviceById, serviceDuration, servicePrice } from '../lib/catalog';
import { durationLabel } from '../lib/format';
import { useBooking, useStepNavigation } from './BookingContext';
import { STEP_PATHS } from './flow';
import { BookingLayout, StepHeader } from './StepChrome';

/**
 * Step 1: a service, by menu category. Opened from "Book with Carlos" it lists
 * Carlos's own menu instead, at his prices, and picking one goes straight to the
 * times (like the app's barber-first booking).
 */
export function ServiceStep({ catalog }: { catalog: Catalog }) {
  const { draft, dispatch } = useBooking();
  const { goTo } = useStepNavigation('service');
  const [params] = useSearchParams();
  const navigate = useNavigate();

  // /book?service=haircut and /book?barber=carlos-rafael (from Services, Barbers and Home).
  useEffect(() => {
    const serviceParam = params.get('service');
    const barberParam = params.get('barber');
    if (serviceParam === null && barberParam === null) return;
    const service = serviceById(catalog, serviceParam);
    const barber = barberById(catalog, barberParam);
    dispatch({ type: 'begin', serviceId: null, barberId: barber?.id ?? null });
    if (service) {
      const theirs = barber ? catalog.offerings.filter((o) => o.barberId === barber.id && o.serviceId === service.id) : [];
      if (theirs.length === 1) {
        dispatch({ type: 'chooseService', serviceId: service.id, choice: { kind: 'offering', offeringId: theirs[0]!.id } });
        navigate(STEP_PATHS.time, { replace: true, state: { from: STEP_PATHS.service } });
      } else {
        dispatch({ type: 'chooseService', serviceId: service.id });
        navigate(STEP_PATHS.barber, { replace: true, state: { from: STEP_PATHS.service } });
      }
      return;
    }
    navigate(STEP_PATHS.service, { replace: true });
  }, [catalog, dispatch, navigate, params]);

  const barber = barberById(catalog, draft.barberId);

  const pickService = (service: CatalogService) => {
    dispatch({ type: 'chooseService', serviceId: service.id });
    goTo('barber');
  };

  const pickOffering = (offering: Offering) => {
    dispatch({ type: 'chooseService', serviceId: offering.serviceId, choice: { kind: 'offering', offeringId: offering.id } });
    goTo('time');
  };

  return (
    <BookingLayout catalog={catalog}>
      <StepHeader
        step="service"
        title="Pick a service"
        subtitle={barber ? `Everything ${barber.name} offers, at ${barber.name}'s own prices. No payment needed to book.` : 'No payment needed to book. You pay at the shop.'}
      />
      {barber ? (
        <>
          <div className="card card--gray with-barber">
            <Monogram letters={barber.monogram} tone={monogramTone(catalog, barber.id)} />
            <div className="with-barber__text">
              <p className="secondary">Booking with</p>
              <p className="with-barber__name">{barber.name}</p>
            </div>
            <button type="button" className="text-button" onClick={() => dispatch({ type: 'clearBarber' })}>
              See every barber
            </button>
          </div>
          {categories(catalog)
            .map((group) => ({
              ...group,
              offerings: offeringsForBarber(catalog, barber.id).filter((o) => group.services.some((s) => s.id === o.serviceId)),
            }))
            .filter((group) => group.offerings.length > 0)
            .map((group) => (
              <section key={group.anchor} className="choice-group" aria-labelledby={`group-${group.anchor}`}>
                <h2 id={`group-${group.anchor}`} className="choice-group__title">
                  {group.title}
                </h2>
                <ul className="choice-list">
                  {group.offerings.map((offering) => {
                    const service = serviceById(catalog, offering.serviceId);
                    const selected = draft.choice?.kind === 'offering' && draft.choice.offeringId === offering.id;
                    return (
                      <li key={offering.id}>
                        <button
                          type="button"
                          className={`choice choice--no-icon${selected ? ' is-selected' : ''}`}
                          aria-current={selected ? 'true' : undefined}
                          onClick={() => pickOffering(offering)}
                          data-testid={`offering-${offering.id}`}
                        >
                          <span className="choice__main">
                            <span className="choice__title">{service?.name ?? 'Appointment'}</span>
                            {offering.note ? <span className="choice__note">{offering.note}</span> : null}
                          </span>
                          <span className="choice__price">
                            <span className="choice__amount">{offering.priceLabel}</span>
                            <span className="choice__detail">{durationLabel(offering.durationMinutes)}</span>
                          </span>
                          <Icon name="chevronRight" className="choice__chevron" />
                        </button>
                      </li>
                    );
                  })}
                </ul>
              </section>
            ))}
        </>
      ) : (
        categories(catalog).map((group) => (
          <section key={group.anchor} className="choice-group" aria-labelledby={`group-${group.anchor}`}>
            <h2 id={`group-${group.anchor}`} className="choice-group__title">
              {group.title}
            </h2>
            <ul className="choice-list">
              {group.services.map((service) => (
                <li key={service.id}>
                  <button
                    type="button"
                    className={`choice choice--no-icon${draft.serviceId === service.id ? ' is-selected' : ''}`}
                    aria-current={draft.serviceId === service.id ? 'true' : undefined}
                    onClick={() => pickService(service)}
                    data-testid={`service-${service.id}`}
                  >
                    <span className="choice__main">
                      <span className="choice__title">{service.name}</span>
                      {service.description ? <span className="choice__detail">{service.description}</span> : null}
                    </span>
                    <span className="choice__price">
                      <span className="choice__amount">{servicePrice(catalog, service.id)}</span>
                      <span className="choice__detail">{serviceDuration(catalog, service.id)}</span>
                    </span>
                    <Icon name="chevronRight" className="choice__chevron" />
                  </button>
                </li>
              ))}
            </ul>
          </section>
        ))
      )}
    </BookingLayout>
  );
}
