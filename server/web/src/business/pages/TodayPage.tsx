// Today: the shop's day. A date with ‹ › and Today; the appointments in barber columns on
// a computer, in one list on a phone; an appointment's details in a panel at the side,
// with Check out, the status buttons and the fee; and the day's sales, with Void. It
// loads again every minute while it's on screen, and after every change.

import { useCallback, useState, useSyncExternalStore, type ReactElement } from 'react';
import { useSearchParams } from 'react-router-dom';
import type { Catalog } from '../../api/types';
import { Icon } from '../../components/Icon';
import { Monogram } from '../../components/ui';
import { useCatalog } from '../../data/catalog';
import { addDays, daysBetween, localDate, longDateLabel, timeLabel, WEEKDAY_NAMES, weekdayOf } from '../../lib/shopTime';
import { ownerApi } from '../api/client';
import { Badges, ErrorBanner, PageHeader, SidePanel, Skeleton, SkeletonCard } from '../components/common';
import { useBusinessTitle, useClock, useLoad } from '../hooks';
import { appointmentBadges } from '../lib/fees';
import { moneyWithCommas } from '../lib/money';
import { appointmentTicket, lastBarber, walkInTicket, type Ticket } from '../lib/ticket';
import type { OwnerAppointment, Product, Sale, SalesDay, TimeOff, VoidedSale } from '../types';
import { AppointmentDetails, timeRange } from './today/AppointmentDetails';
import { Checkout, Receipt } from './today/Checkout';
import { SalesList, useVoidSale } from './today/SalesList';

interface DayView {
  appointments: OwnerAppointment[];
  timeOff: TimeOff[];
  sales: SalesDay;
}

type PanelState =
  | { kind: 'appointment'; id: string }
  | { kind: 'checkout'; ticket: Ticket; appointmentId: string | null }
  | { kind: 'receipt'; sale: Sale }
  | null;

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function subscribeWide(listener: () => void): () => void {
  if (typeof window.matchMedia !== 'function') return () => undefined;
  const query = window.matchMedia('(min-width: 1000px)');
  query.addEventListener?.('change', listener);
  return () => query.removeEventListener?.('change', listener);
}

/** Wide enough for a column per barber. */
function useWide(): boolean {
  return useSyncExternalStore(
    subscribeWide,
    () => typeof window.matchMedia === 'function' && window.matchMedia('(min-width: 1000px)').matches,
    () => false,
  );
}

/** "Today", "Tomorrow", "Yesterday", or the weekday. */
export function relativeDay(date: string, today: string): string {
  const offset = daysBetween(today, date);
  if (offset === 0) return 'Today';
  if (offset === 1) return 'Tomorrow';
  if (offset === -1) return 'Yesterday';
  return WEEKDAY_NAMES[weekdayOf(date) - 1]!;
}

function AppointmentCard({ appointment, zone, onOpen, showBarber }: { appointment: OwnerAppointment; zone: string; onOpen: () => void; showBarber: boolean }) {
  const cancelled = appointment.status === 'cancelled';
  return (
    <button type="button" className={`biz-appt biz-appt--${appointment.status}`} onClick={onOpen} data-testid="appointment">
      <span className="biz-appt__time">{timeRange(appointment, zone)}</span>
      <span className={`biz-appt__client${cancelled ? ' biz-struck' : ''}`}>{appointment.customer.name}</span>
      <span className="biz-appt__service">
        {appointment.serviceName}
        {showBarber ? ` · ${appointment.barberName}` : ''}
      </span>
      <Badges badges={appointmentBadges(appointment)} />
    </button>
  );
}

function BlockCard({ block, zone }: { block: TimeOff; zone: string }) {
  return (
    <div className="biz-block">
      <span className="biz-appt__time">{timeRange(block, zone)}</span>
      <span>Blocked{block.reason ? `: ${block.reason}` : ''}</span>
    </div>
  );
}

function Board({ catalog, view, onOpen }: { catalog: Catalog; view: DayView; onOpen: (id: string) => void }) {
  const zone = catalog.timeZone;
  return (
    <div className="biz-board" role="list" aria-label="Appointments by barber">
      {catalog.barbers.map((barber) => {
        const appointments = view.appointments.filter((a) => a.barberId === barber.id);
        const blocks = view.timeOff.filter((b) => b.barberId === barber.id);
        const booked = appointments.filter((a) => a.status !== 'cancelled').length;
        const items = [
          ...appointments.map((a) => ({
            start: a.start,
            node: <AppointmentCard key={a.id} appointment={a} zone={zone} onOpen={() => onOpen(a.id)} showBarber={false} />,
          })),
          ...blocks.map((b) => ({ start: b.start, node: <BlockCard key={b.id} block={b} zone={zone} /> })),
        ].sort((a, b) => a.start.localeCompare(b.start));
        return (
          <section key={barber.id} className="biz-column" role="listitem" aria-labelledby={`column-${barber.id}`}>
            <header className="biz-column__head">
              <Monogram letters={barber.monogram} tone="ink" size="small" />
              <div>
                <h2 id={`column-${barber.id}`} className="biz-column__name">
                  {barber.name}
                </h2>
                <p className="biz-column__count">{booked === 0 ? 'Nothing booked' : `${booked} ${booked === 1 ? 'appointment' : 'appointments'}`}</p>
              </div>
            </header>
            <div className="biz-column__items">{items.map((item) => item.node)}</div>
          </section>
        );
      })}
    </div>
  );
}

function List({ catalog, view, onOpen }: { catalog: Catalog; view: DayView; onOpen: (id: string) => void }) {
  const zone = catalog.timeZone;
  const blocks = view.timeOff.filter((b) => b.barberId !== null);
  return (
    <div className="biz-list">
      <ul className="biz-list__items" role="list" aria-label="Appointments">
        {view.appointments.map((appointment) => (
          <li key={appointment.id}>
            <AppointmentCard appointment={appointment} zone={zone} onOpen={() => onOpen(appointment.id)} showBarber />
          </li>
        ))}
      </ul>
      {blocks.length > 0 ? (
        <section aria-labelledby="blocked-title" className="biz-list__blocks">
          <h2 id="blocked-title" className="biz-section-title">
            Blocked time
          </h2>
          {blocks.map((block) => (
            <div key={block.id} className="biz-block">
              <span className="biz-appt__time">{timeRange(block, zone)}</span>
              <span>
                {catalog.barbers.find((b) => b.id === block.barberId)?.name}
                {block.reason ? `: ${block.reason}` : ''}
              </span>
            </div>
          ))}
        </section>
      ) : null}
    </div>
  );
}

function DayControls({ date, today, onDate }: { date: string; today: string; onDate: (date: string) => void }) {
  return (
    <div className="biz-day">
      <button type="button" className="biz-day__step" onClick={() => onDate(addDays(date, -1))} aria-label="Previous day">
        <Icon name="chevronLeft" />
      </button>
      <label className="biz-day__date">
        <span className="visually-hidden">Day</span>
        <input type="date" className="biz-day__input" value={date} onChange={(e) => DATE_RE.test(e.target.value) && onDate(e.target.value)} />
      </label>
      <button type="button" className="biz-day__step" onClick={() => onDate(addDays(date, 1))} aria-label="Next day">
        <Icon name="chevronRight" />
      </button>
      {date !== today ? (
        <button type="button" className="button button--secondary biz-day__today" onClick={() => onDate(today)}>
          Today
        </button>
      ) : null}
    </div>
  );
}

function summaryLine(view: DayView): string {
  const live = view.appointments.filter((a) => a.status !== 'cancelled');
  const done = live.filter((a) => a.status === 'completed').length;
  const parts = [`${live.length} ${live.length === 1 ? 'appointment' : 'appointments'}`, `${done} done`];
  parts.push(`${moneyWithCommas(view.sales.totals.totalCents)} in sales`);
  return parts.join(' · ');
}

export function TodayPage() {
  useBusinessTitle('Today', 'The shop’s day in Izzy Clipz Business: appointments, checkout and the day’s sales.');
  const catalog = useCatalog();
  const zone = catalog?.timeZone ?? 'America/Los_Angeles';
  const now = useClock();
  const today = localDate(now, zone);
  const [params, setParams] = useSearchParams();
  const asked = params.get('date');
  const date = asked && DATE_RE.test(asked) ? asked : today;
  const wide = useWide();

  const day = useLoad<DayView>(
    `day|${date}`,
    async (signal) => {
      const [appointments, timeOff, sales] = await Promise.all([
        ownerApi.appointments(date, signal),
        ownerApi.timeOff(date, signal),
        ownerApi.sales(date, signal),
      ]);
      return { appointments, timeOff, sales };
    },
    { refreshMs: 60_000 },
  );

  const [panel, setPanel] = useState<PanelState>(null);
  const [products, setProducts] = useState<Product[] | null>(null);
  const [voidMessage, setVoidMessage] = useState<string | null>(null);

  const setDate = (next: string) => {
    setPanel(null);
    setVoidMessage(null);
    setParams(next === today ? {} : { date: next }, { replace: true });
  };

  const loadProducts = useCallback(() => {
    setProducts(null);
    ownerApi
      .products()
      .then(setProducts)
      .catch(() => setProducts([]));
  }, []);

  const voids = useVoidSale((result: VoidedSale) => {
    setVoidMessage(result.message);
    day.reload();
  });

  const view = day.data;
  const appointment = panel?.kind === 'appointment' ? (view?.appointments.find((a) => a.id === panel.id) ?? null) : null;

  const replaceAppointment = (changed: OwnerAppointment) => {
    if (view) day.replace({ ...view, appointments: view.appointments.map((a) => (a.id === changed.id ? changed : a)) });
    day.reload();
  };

  const startCheckout = (from: OwnerAppointment | null) => {
    if (!catalog) return;
    loadProducts();
    const remembered = lastBarber();
    const ticket = from ? appointmentTicket(from, catalog.offerings) : walkInTicket(catalog.barbers.some((b) => b.id === remembered) ? remembered : null);
    setPanel({ kind: 'checkout', ticket, appointmentId: from?.id ?? null });
  };

  const voidFromDetails = (saleId: string) => {
    const found = view?.sales.sales.find((s) => s.id === saleId);
    if (found) {
      voids.ask(found, zone);
      return;
    }
    // Checked out on another day: what the appointment knows of its sale.
    if (appointment?.sale) {
      voids.ask(
        {
          id: appointment.sale.id,
          barberId: appointment.barberId,
          barberName: appointment.barberName,
          appointmentId: appointment.id,
          customerName: appointment.customer.name,
          method: appointment.sale.method,
          paymentIntentId: null,
          totalCents: appointment.sale.totalCents,
          items: [
            {
              kind: 'service',
              serviceId: appointment.serviceId,
              productId: null,
              name: appointment.serviceName,
              quantity: 1,
              unitCents: appointment.sale.totalCents,
              totalCents: appointment.sale.totalCents,
            },
          ],
          soldAt: appointment.payment.paidAt ?? appointment.end,
          voidedAt: null,
          voidReason: null,
        },
        zone,
      );
    }
  };

  let panelTitle = '';
  let panelBody: ReactElement | null = null;
  let panelBack: { label: string; onBack: () => void } | undefined;
  if (panel?.kind === 'appointment' && appointment && catalog) {
    panelTitle = appointment.customer.name;
    panelBody = (
      <AppointmentDetails
        appointment={appointment}
        zone={zone}
        now={now}
        onChanged={replaceAppointment}
        onCheckOut={() => startCheckout(appointment)}
        onVoidSale={voidFromDetails}
      />
    );
  } else if (panel?.kind === 'checkout' && catalog) {
    panelTitle = 'Check out';
    const from = panel.appointmentId;
    if (from) panelBack = { label: 'Appointment', onBack: () => setPanel({ kind: 'appointment', id: from }) };
    panelBody = (
      <Checkout
        ticket={panel.ticket}
        onChange={(ticket) => setPanel({ ...panel, ticket })}
        catalog={catalog}
        products={products}
        onSold={(sale) => {
          setPanel({ kind: 'receipt', sale });
          setVoidMessage(null);
          day.reload();
        }}
      />
    );
  } else if (panel?.kind === 'receipt') {
    panelTitle = 'Sold';
    panelBody = <Receipt sale={panel.sale} zone={zone} />;
  }

  const isToday = date === today;
  const loading = view === null;

  return (
    <div className="container container--wide biz-page" data-testid="today-page">
      <PageHeader
        eyebrow={relativeDay(date, today)}
        title={longDateLabel(date)}
        lead={isToday ? "Your shop's day: appointments, checkout and today's sales." : `Appointments and sales for ${longDateLabel(date)}.`}
      >
        <DayControls date={date} today={today} onDate={setDate} />
      </PageHeader>

      {day.status === 'error' ? (
        <ErrorBanner
          title={view ? "Couldn't refresh" : "Couldn't load the day"}
          message={view ? `${day.error} Showing what was loaded before.` : day.error}
          onRetry={day.reload}
        />
      ) : null}

      {view ? (
        <p className="biz-summary" data-testid="day-summary">
          {summaryLine(view)}
          {day.updatedAt ? <span className="biz-summary__updated"> · Updated {timeLabel(day.updatedAt, zone)}. Refreshes every minute.</span> : null}
        </p>
      ) : (
        <Skeleton height={22} width="40%" />
      )}

      {view && catalog ? (
        view.appointments.length === 0 && view.timeOff.length === 0 ? (
          <div className="biz-empty" data-testid="day-empty">
            <h2>Nothing booked for {longDateLabel(date)}.</h2>
            <p className="secondary">Bookings from the website and the app show up here. Walk-ins can still be checked out with New sale.</p>
          </div>
        ) : (
          <>
            {view.timeOff
              .filter((b) => b.barberId === null)
              .map((block) => (
                <p key={block.id} className="notice notice--info biz-shop-block">
                  The shop is blocked {timeRange(block, zone)}
                  {block.reason ? `: ${block.reason}` : ''}.
                </p>
              ))}
            {wide ? (
              <Board catalog={catalog} view={view} onOpen={(id) => setPanel({ kind: 'appointment', id })} />
            ) : (
              <List catalog={catalog} view={view} onOpen={(id) => setPanel({ kind: 'appointment', id })} />
            )}
          </>
        )
      ) : loading && day.status !== 'error' ? (
        <div className="biz-board biz-board--loading">
          {[0, 1, 2].map((i) => (
            <SkeletonCard key={i} label="Loading the day…" />
          ))}
        </div>
      ) : null}

      <SalesList
        day={view?.sales ?? null}
        title={isToday ? "Today's sales" : `Sales on ${longDateLabel(date)}`}
        zone={zone}
        message={voidMessage}
        onVoid={(sale) => voids.ask(sale, zone)}
        onNewSale={() => startCheckout(null)}
      />

      <SidePanel
        open={panelBody !== null}
        title={panelTitle}
        onClose={() => setPanel(null)}
        back={panelBack}
        testId="side-panel"
        footer={
          panel?.kind === 'receipt' ? (
            <button type="button" className="button button--primary button--large button--block" onClick={() => setPanel(null)}>
              Done
            </button>
          ) : undefined
        }
      >
        {panelBody}
      </SidePanel>
      {voids.dialog}
    </div>
  );
}
