import type { Catalog, Offering } from '../api/types';
import { Icon } from '../components/Icon';
import { Monogram } from '../components/ui';
import { anyBarberOption, barberById, barbersForService, monogramTone, offeringsForService, serviceById, serviceDuration, servicePriceRange } from '../lib/catalog';
import { durationLabel, list } from '../lib/format';
import { useBooking, useStepNavigation } from './BookingContext';
import type { Choice } from './flow';
import { BookingLayout, StepHeader } from './StepChrome';

/**
 * Step 2: who does it. "Any barber" comes first when several barbers share the
 * service, then each barber's own version with their price and length (Flowxbori
 * has two haircuts, so he's listed twice).
 */
export function BarberStep({ catalog }: { catalog: Catalog }) {
  const { draft, dispatch } = useBooking();
  const { goTo } = useStepNavigation('barber');
  const serviceId = draft.serviceId ?? '';
  const service = serviceById(catalog, serviceId);
  const option = anyBarberOption(catalog, serviceId);
  const offerings = offeringsForService(catalog, serviceId);
  const perBarber = new Map<string, number>();
  for (const o of offerings) perBarber.set(o.barberId, (perBarber.get(o.barberId) ?? 0) + 1);
  const onlyBarber = barbersForService(catalog, serviceId);

  const pick = (choice: Choice) => {
    dispatch({ type: 'chooseBarber', choice });
    goTo('time');
  };

  const subtitle = [service?.name, servicePriceRange(catalog, serviceId), serviceDuration(catalog, serviceId)].filter(Boolean).join(' · ');

  return (
    <BookingLayout catalog={catalog}>
      <StepHeader step="barber" title="Pick a barber" subtitle={subtitle} />
      <ul className="choice-list">
        {option ? (
          <li>
            <button
              type="button"
              className={`choice${draft.choice?.kind === 'any' ? ' is-selected' : ''}`}
              aria-current={draft.choice?.kind === 'any' ? 'true' : undefined}
              onClick={() => pick({ kind: 'any' })}
              data-testid="any-barber"
            >
              <span className="choice__icon any-barber-icon" aria-hidden="true">
                <Icon name="clock" />
              </span>
              <span className="choice__main">
                <span className="choice__title">Any barber</span>
                <span className="choice__detail">Whoever is free first: {list(option.barbers.map((b) => b.name))}</span>
              </span>
              <span className="choice__price">
                <span className="choice__amount">{option.priceLabel}</span>
                <span className="choice__detail">{option.durationLabel}</span>
              </span>
              <Icon name="chevronRight" className="choice__chevron" />
            </button>
          </li>
        ) : null}
      </ul>
      {option ? <h2 className="choice-group__title">Or pick your barber</h2> : null}
      <ul className="choice-list">
        {offerings.map((offering) => (
          <li key={offering.id}>
            <OfferingChoice
              catalog={catalog}
              offering={offering}
              showsLength={(perBarber.get(offering.barberId) ?? 0) > 1}
              selected={draft.choice?.kind === 'offering' && draft.choice.offeringId === offering.id}
              onPick={() => pick({ kind: 'offering', offeringId: offering.id })}
            />
          </li>
        ))}
      </ul>
      {onlyBarber.length === 1 && service ? (
        <p className="secondary">
          Only {onlyBarber[0]!.name} offers {service.name}.
        </p>
      ) : null}
    </BookingLayout>
  );
}

function OfferingChoice({
  catalog,
  offering,
  showsLength,
  selected,
  onPick,
}: {
  catalog: Catalog;
  offering: Offering;
  showsLength: boolean;
  selected: boolean;
  onPick: () => void;
}) {
  const barber = barberById(catalog, offering.barberId);
  const name = barber?.name ?? 'Barber';
  return (
    <button
      type="button"
      className={`choice${selected ? ' is-selected' : ''}`}
      aria-current={selected ? 'true' : undefined}
      onClick={onPick}
      data-testid={`barber-${offering.id}`}
    >
      <Monogram letters={barber?.monogram ?? name.slice(0, 2).toUpperCase()} tone={monogramTone(catalog, offering.barberId)} />
      <span className="choice__main">
        <span className="choice__title">{showsLength ? `${name}, ${durationLabel(offering.durationMinutes)}` : name}</span>
        <span className="choice__detail">{barber?.title ?? 'Barber'}</span>
        {offering.note ? <span className="choice__note">{offering.note}</span> : null}
      </span>
      <span className="choice__price">
        <span className="choice__amount">{offering.priceLabel}</span>
        <span className="choice__detail">{durationLabel(offering.durationMinutes)}</span>
      </span>
      <Icon name="chevronRight" className="choice__chevron" />
    </button>
  );
}
