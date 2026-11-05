// Analytics, laid out for a computer: how the shop is doing, live, for the whole shop or
// one barber, over Today, this week, this month, this year or chosen dates. Total sales
// with the change from before and the split, the top sales barber, daily sales, the
// leaderboard (by sales, services, products or clients served), top services, products
// sold, and productivity, each tile with its meaning a click away (docs/analytics.md).
// It refreshes every 30 seconds while it's on screen ("Live · Updated 10:42 AM"), never
// two requests at once, and keeps what's shown while it refreshes or if a refresh fails.

import { useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import type { Catalog } from '../../api/types';
import { Dialog } from '../../components/Dialog';
import { Icon } from '../../components/Icon';
import { Monogram } from '../../components/ui';
import { useCatalog } from '../../data/catalog';
import { money } from '../../lib/format';
import { localDate, timeLabel } from '../../lib/shopTime';
import { ownerApi } from '../api/client';
import { ChartFrame, Crown, DailyChart, DailyTable, Legend, Medal, RowBar, SERIES, SplitBar } from '../components/charts';
import { ErrorBanner, PageHeader, Skeleton } from '../components/common';
import { useBusinessTitle, useClock, useLoad } from '../hooks';
import { METRICS, metricLabel, rankBy, type Metric } from '../lib/leaderboard';
import { moneyWithCommas, percent } from '../lib/money';
import { changeDirection, changeText, periodRange, periodTitle, rangeLabel, rangeProblem, type PeriodKind, type Range } from '../lib/periods';
import type { Analytics } from '../types';

/** How often Analytics refreshes while it's on screen. */
export const LIVE_REFRESH_MS = 30_000;

const PERIODS: { id: Exclude<PeriodKind, 'custom'>; label: string }[] = [
  { id: 'today', label: 'Today' },
  { id: 'week', label: 'Week' },
  { id: 'month', label: 'Month' },
  { id: 'year', label: 'Year' },
];

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function Scope({ catalog, barberId, onChange }: { catalog: Catalog; barberId: string | null; onChange: (id: string | null) => void }) {
  return (
    <fieldset className="biz-chips biz-scope">
      <legend className="visually-hidden">Whose numbers</legend>
      <div className="biz-chips__list">
        <label className="biz-chip">
          <input type="radio" name="scope" className="biz-chip__input" checked={barberId === null} onChange={() => onChange(null)} />
          <span className="biz-chip__label">Whole shop</span>
        </label>
        {catalog.barbers.map((barber) => (
          <label key={barber.id} className="biz-chip">
            <input type="radio" name="scope" className="biz-chip__input" checked={barberId === barber.id} onChange={() => onChange(barber.id)} />
            <span className="biz-chip__label">
              <Monogram letters={barber.monogram} tone="ink" size="small" />
              {barber.name}
            </span>
          </label>
        ))}
      </div>
    </fieldset>
  );
}

function Periods({
  kind,
  onChange,
  onCustom,
  customLabel,
}: {
  kind: PeriodKind;
  onChange: (kind: Exclude<PeriodKind, 'custom'>) => void;
  onCustom: () => void;
  customLabel: string | null;
}) {
  return (
    <div className="biz-periods">
      <fieldset className="biz-periods__set">
        <legend className="visually-hidden">Period</legend>
        <div className="segmented">
          {PERIODS.map((period) => (
            <label key={period.id} className="segmented__option">
              <input type="radio" className="segmented__input" name="period" checked={kind === period.id} onChange={() => onChange(period.id)} />
              <span className="segmented__label">{period.label}</span>
            </label>
          ))}
        </div>
      </fieldset>
      <button
        type="button"
        className={`button button--secondary biz-periods__custom${kind === 'custom' ? ' is-on' : ''}`}
        aria-pressed={kind === 'custom'}
        onClick={onCustom}
      >
        {kind === 'custom' && customLabel ? customLabel : 'Custom…'}
      </button>
    </div>
  );
}

function CustomDialog({
  open,
  initial,
  today,
  onApply,
  onClose,
}: {
  open: boolean;
  initial: Range;
  today: string;
  onApply: (range: Range) => void;
  onClose: () => void;
}) {
  const [from, setFrom] = useState(initial.from);
  const [to, setTo] = useState(initial.to);
  const [problem, setProblem] = useState<string | null>(null);
  const apply = () => {
    const range = { from, to };
    const wrong = rangeProblem(range, today);
    if (wrong) {
      setProblem(wrong);
      return;
    }
    onApply(range);
  };
  return (
    <Dialog
      open={open}
      title="Pick the dates"
      onClose={onClose}
      testId="custom-dates"
      actions={
        <>
          <button type="button" className="button button--secondary" onClick={onClose}>
            Cancel
          </button>
          <button type="button" className="button button--primary" onClick={apply}>
            Show these dates
          </button>
        </>
      }
    >
      <p>Up to 366 days (about a year), on the shop's calendar.</p>
      <div className="biz-custom">
        <div className="field">
          <label className="field__label" htmlFor="custom-from">
            From
          </label>
          <input
            id="custom-from"
            type="date"
            className="field__input"
            value={from}
            max={to || undefined}
            onChange={(e) => (setFrom(e.target.value), setProblem(null))}
          />
        </div>
        <div className="field">
          <label className="field__label" htmlFor="custom-to">
            To
          </label>
          <input
            id="custom-to"
            type="date"
            className="field__input"
            value={to}
            min={from || undefined}
            onChange={(e) => (setTo(e.target.value), setProblem(null))}
          />
        </div>
      </div>
      {problem ? (
        <p className="field__error" role="alert">
          <Icon name="error" />
          <span>{problem}</span>
        </p>
      ) : null}
    </Dialog>
  );
}

function Live({ updatedAt, loading, zone }: { updatedAt: Date | null; loading: boolean; zone: string }) {
  return (
    <p className="biz-live" data-testid="live">
      <span className={`biz-live__dot${updatedAt ? '' : ' is-waiting'}`} aria-hidden="true" />
      {updatedAt ? `Live · Updated ${timeLabel(updatedAt, zone)}` : loading ? 'Loading…' : 'Not loaded yet'}
    </p>
  );
}

function TotalSales({ data, range, today, isToday }: { data: Analytics; range: Range; today: string; isToday: boolean }) {
  const t = data.totals;
  const parts = [
    { ...SERIES.services, value: t.servicesCents },
    { ...SERIES.products, value: t.productsCents },
    { ...SERIES.other, value: t.otherCents },
    { ...SERIES.fees, value: t.feesCents },
  ];
  const direction = changeDirection(t.salesCents, data.previous.salesCents);
  const empty = t.salesCents === 0;
  return (
    <section className="biz-card biz-total-sales" aria-labelledby="total-sales-title" data-testid="total-sales">
      <h2 id="total-sales-title" className="biz-card__title">
        Total sales
      </h2>
      <p className="biz-hero-number" data-testid="total-sales-value">
        {moneyWithCommas(t.salesCents)}
      </p>
      <p className={`biz-change biz-change--${direction}`} data-testid="total-sales-change">
        {direction !== 'none' ? <span aria-hidden="true">{direction === 'up' ? '▲ ' : '▼ '}</span> : null}
        {changeText(t.salesCents, data.previous.salesCents, range, today)}
      </p>
      {empty ? (
        <p className="biz-empty-line" data-testid="no-sales">
          {isToday ? 'No sales yet today. Sales show up here as you check clients out.' : 'No sales in this period.'}
        </p>
      ) : (
        <>
          <SplitBar parts={parts} label={parts.map((p) => `${p.label} ${money(p.value)}`).join(', ')} />
          <Legend items={parts.map((p) => ({ label: p.label, color: p.color, value: moneyWithCommas(p.value) }))} />
        </>
      )}
      <dl className="biz-mini-stats">
        <div>
          <dt>Clients served</dt>
          <dd>{t.clientsServed}</dd>
        </div>
        <div>
          <dt>Services</dt>
          <dd>{t.servicesCount}</dd>
        </div>
        <div>
          <dt>Products sold</dt>
          <dd>{t.productsCount}</dd>
        </div>
        <div>
          <dt>Average ticket</dt>
          <dd>{money(t.averageTicketCents)}</dd>
        </div>
      </dl>
    </section>
  );
}

function TopBarber({ data }: { data: Analytics }) {
  const top = data.topBarber;
  return (
    <section className="biz-card biz-top-barber" aria-labelledby="top-barber-title" data-testid="top-barber">
      <h2 id="top-barber-title" className="biz-card__title">
        Top sales barber{data.barberId ? ' (whole shop)' : ''}
      </h2>
      {top ? (
        <div className="biz-top-barber__body">
          <Crown />
          <p className="biz-top-barber__name">{top.name}</p>
          <p className="biz-top-barber__total">{moneyWithCommas(top.salesCents)}</p>
          <p className="secondary">
            {top.servicesCount} {top.servicesCount === 1 ? 'service' : 'services'} · {top.productsCount} {top.productsCount === 1 ? 'product' : 'products'}
          </p>
        </div>
      ) : (
        <p className="biz-empty-line">No sales in this period yet. The barber with the most sales shows here.</p>
      )}
    </section>
  );
}

function Leaderboard({ data, selected }: { data: Analytics; selected: string | null }) {
  const [metric, setMetric] = useState<Metric>('sales');
  const ranked = rankBy(data.leaderboard, metric);
  const max = Math.max(...ranked.map((r) => r.value), 0);
  return (
    <section className="biz-card biz-leaderboard" aria-labelledby="leaderboard-title" data-testid="leaderboard">
      <h2 id="leaderboard-title" className="biz-card__title">
        Leaderboard
      </h2>
      <p className="secondary small">The whole shop, so each barber sees where he stands.</p>
      <fieldset className="biz-metrics">
        <legend className="visually-hidden">Rank by</legend>
        <div className="segmented segmented--small">
          {METRICS.map((m) => (
            <label key={m.id} className="segmented__option">
              <input type="radio" className="segmented__input" name="metric" checked={metric === m.id} onChange={() => setMetric(m.id)} />
              <span className="segmented__label">{m.label}</span>
            </label>
          ))}
        </div>
      </fieldset>
      <ol className="biz-ranks" role="list">
        {ranked.map(({ entry, place, value }) => (
          <li key={entry.barberId} className={`biz-rank${entry.barberId === selected ? ' is-selected' : ''}`} data-testid="leaderboard-row">
            <span className="biz-rank__place">
              {place <= 3 && value > 0 ? <Medal place={place as 1 | 2 | 3} /> : <span className="biz-rank__number">{place}</span>}
            </span>
            <span className="biz-rank__name">
              {entry.name}
              {entry.barberId === selected ? <span className="visually-hidden"> (picked)</span> : null}
            </span>
            <span className="biz-rank__value">{metricLabel(entry, metric)}</span>
            <span className="biz-rank__bar">
              <RowBar value={value} max={max} highlight={entry.barberId === selected} />
            </span>
          </li>
        ))}
      </ol>
    </section>
  );
}

function TodayByBarber({ data }: { data: Analytics }) {
  const max = Math.max(...data.leaderboard.map((e) => e.salesCents), 0);
  const rows = data.leaderboard;
  return (
    <section className="biz-card biz-wide-card" aria-labelledby="by-barber-title" data-testid="today-by-barber">
      <h2 id="by-barber-title" className="biz-card__title">
        Today by barber
      </h2>
      <ChartFrame
        title="today by barber"
        table={
          <div className="biz-table-wrap" tabIndex={0} role="region" aria-label="Table">
            <table className="biz-table">
              <caption className="visually-hidden">Today's sales by barber</caption>
              <thead>
                <tr>
                  <th scope="col">Barber</th>
                  <th scope="col">Sales</th>
                  <th scope="col">Services</th>
                  <th scope="col">Products</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((e) => (
                  <tr key={e.barberId}>
                    <th scope="row">{e.name}</th>
                    <td>{moneyWithCommas(e.salesCents)}</td>
                    <td>{e.servicesCount}</td>
                    <td>{e.productsCount}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        }
      >
        <ul className="biz-bars" role="list">
          {rows.map((e) => (
            <li key={e.barberId} className="biz-bars__row">
              <span className="biz-bars__label">{e.name}</span>
              <span className="biz-bars__bar">
                <RowBar value={e.salesCents} max={max} />
              </span>
              <span className="biz-bars__value">{moneyWithCommas(e.salesCents)}</span>
            </li>
          ))}
        </ul>
      </ChartFrame>
    </section>
  );
}

function TopServices({ data }: { data: Analytics }) {
  const max = Math.max(...data.services.map((s) => s.salesCents), 0);
  return (
    <section className="biz-card" aria-labelledby="services-title" data-testid="top-services">
      <h2 id="services-title" className="biz-card__title">
        Top services
      </h2>
      {data.services.length === 0 ? (
        <p className="biz-empty-line">No services in this period yet.</p>
      ) : (
        <ChartFrame
          title="top services"
          table={
            <div className="biz-table-wrap" tabIndex={0} role="region" aria-label="Table">
              <table className="biz-table">
                <caption className="visually-hidden">Sales by service</caption>
                <thead>
                  <tr>
                    <th scope="col">Service</th>
                    <th scope="col">How many</th>
                    <th scope="col">Sales</th>
                  </tr>
                </thead>
                <tbody>
                  {data.services.map((s) => (
                    <tr key={s.serviceId}>
                      <th scope="row">{s.name}</th>
                      <td>{s.count}</td>
                      <td>{moneyWithCommas(s.salesCents)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          }
        >
          <ul className="biz-bars" role="list">
            {data.services.map((s) => (
              <li key={s.serviceId} className="biz-bars__row" data-testid="service-row">
                <span className="biz-bars__label">{s.name}</span>
                <span className="biz-bars__bar">
                  <RowBar value={s.salesCents} max={max} />
                </span>
                <span className="biz-bars__value">
                  {s.count} · {moneyWithCommas(s.salesCents)}
                </span>
              </li>
            ))}
          </ul>
        </ChartFrame>
      )}
    </section>
  );
}

function ProductsSold({ data }: { data: Analytics }) {
  return (
    <section className="biz-card" aria-labelledby="products-title" data-testid="products-sold">
      <h2 id="products-title" className="biz-card__title">
        Products sold
      </h2>
      {data.products.length === 0 ? (
        <p className="biz-empty-line">No products sold in this period.</p>
      ) : (
        <ul className="biz-plain-list" role="list">
          {data.products.map((p) => (
            <li key={p.productId ?? `deleted:${p.name}`} className="biz-plain-list__row" data-testid="product-row">
              <span>{p.name}</span>
              <span className="secondary">{p.quantity} sold</span>
              <span className="biz-plain-list__value">{moneyWithCommas(p.salesCents)}</span>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

interface TileSpec {
  id: string;
  label: string;
  value: string;
  caption: string;
  info: string;
}

function tiles(data: Analytics): TileSpec[] {
  const p = data.productivity;
  const a = p.appointments;
  return [
    {
      id: 'chair',
      label: 'Chair time booked',
      value: percent(Math.min(1, Math.max(0, p.chairTimeBooked))),
      caption: 'of open hours had a client',
      info: 'Booked time divided by open hours. Open hours are each barber’s hours on days up to today, less time off. It can pass 100% when barbers work past closing; this shows at most 100%.',
    },
    {
      id: 'clients',
      label: 'Clients served',
      value: String(data.totals.clientsServed),
      caption: data.totals.clientsServed === 1 ? 'client' : 'clients',
      info: 'Appointments marked Done (or checked out), plus sales to walk-ins.',
    },
    {
      id: 'ticket',
      label: 'Average ticket',
      value: money(data.totals.averageTicketCents),
      caption: 'per checkout',
      info: 'Services, products and other, divided by checkouts (sales, plus appointments marked Done without a checkout). Fees aren’t part of it.',
    },
    {
      id: 'hourly',
      label: 'Sales per open hour',
      value: money(p.salesPerHourCents),
      caption: 'per open hour',
      info: 'Services, products and other, divided by the open hours.',
    },
    {
      id: 'noshows',
      label: 'No-shows',
      value: String(a.noShows),
      caption: `${percent(p.noShowRate)} of visits`,
      info: 'Appointments marked as no-shows. The share is no-shows divided by Done plus no-shows.',
    },
    {
      id: 'late',
      label: 'Late cancellations',
      value: String(a.lateCancellations),
      caption: `of ${a.cancelled} ${a.cancelled === 1 ? 'cancellation' : 'cancellations'}`,
      info: 'Clients who cancelled in the app later than their booking’s policy allowed for free (for example, less than 1 hour before).',
    },
    {
      id: 'completion',
      label: 'Completion rate',
      value: percent(p.completionRate),
      caption: `${a.completed} done`,
      info: 'Done divided by Done plus no-shows.',
    },
    {
      id: 'attach',
      label: 'Product attach rate',
      value: percent(p.productAttachRate),
      caption: 'of sales included a product',
      info: 'The share of sales that included at least one product.',
    },
    {
      id: 'upcoming',
      label: 'Upcoming',
      value: String(a.upcoming),
      caption: a.upcoming === 1 ? 'appointment still to come' : 'appointments still to come',
      info: 'Booked appointments that haven’t started yet.',
    },
  ];
}

function Tile({ tile }: { tile: TileSpec }) {
  const [open, setOpen] = useState(false);
  const infoId = `tile-info-${tile.id}`;
  return (
    <li className="biz-tile" data-testid={`tile-${tile.id}`}>
      <div className="biz-tile__top">
        <p className="biz-tile__label">{tile.label}</p>
        <button type="button" className="biz-tile__info" aria-expanded={open} aria-controls={infoId} onClick={() => setOpen(!open)}>
          <Icon name="info" />
          <span className="visually-hidden">What {tile.label.toLowerCase()} means</span>
        </button>
      </div>
      <p className="biz-tile__value">{tile.value}</p>
      <p className="biz-tile__caption">{tile.caption}</p>
      {open ? (
        <p className="biz-tile__explain" id={infoId}>
          {tile.info}
        </p>
      ) : null}
    </li>
  );
}

function Productivity({ data }: { data: Analytics }) {
  return (
    <section className="biz-card biz-wide-card" aria-labelledby="productivity-title" data-testid="productivity">
      <h2 id="productivity-title" className="biz-card__title">
        Business productivity
      </h2>
      <ul className="biz-tiles" role="list">
        {tiles(data).map((tile) => (
          <Tile key={tile.id} tile={tile} />
        ))}
      </ul>
    </section>
  );
}

function Loading() {
  return (
    <div className="biz-analytics-grid" role="status" aria-label="Loading the numbers">
      <div className="biz-card biz-total-sales">
        <Skeleton height={20} width="30%" />
        <Skeleton height={56} width="55%" />
        <Skeleton height={18} width="45%" />
        <Skeleton height={10} />
      </div>
      <div className="biz-card biz-top-barber">
        <Skeleton height={20} width="50%" />
        <Skeleton height={80} />
      </div>
      <div className="biz-card biz-wide-card">
        <Skeleton height={240} />
      </div>
    </div>
  );
}

export function AnalyticsPage() {
  useBusinessTitle('Analytics', 'How the shop is doing, live: sales, the leaderboard, top services, products and productivity.');
  const catalog = useCatalog();
  const zone = catalog?.timeZone ?? 'America/Los_Angeles';
  const now = useClock(60_000);
  const today = localDate(now, zone);
  const [params, setParams] = useSearchParams();
  const [customOpen, setCustomOpen] = useState(false);

  const askedBarber = params.get('barber');
  const barberId = askedBarber && catalog?.barbers.some((b) => b.id === askedBarber) ? askedBarber : null;
  const askedPeriod = params.get('period');
  const customFrom = params.get('from');
  const customTo = params.get('to');
  const custom =
    askedPeriod === 'custom' &&
    customFrom &&
    customTo &&
    DATE_RE.test(customFrom) &&
    DATE_RE.test(customTo) &&
    rangeProblem({ from: customFrom, to: customTo }, today) === null;
  const kind: PeriodKind = custom ? 'custom' : PERIODS.some((p) => p.id === askedPeriod) ? (askedPeriod as PeriodKind) : 'today';
  const range: Range = kind === 'custom' ? { from: customFrom!, to: customTo! } : periodRange(kind, today);

  const update = (changes: Record<string, string | null>) => {
    const next = new URLSearchParams(params);
    for (const [key, value] of Object.entries(changes)) {
      if (value === null) next.delete(key);
      else next.set(key, value);
    }
    setParams(next, { replace: true });
  };

  const analytics = useLoad<Analytics>(
    `analytics|${range.from}|${range.to}|${barberId ?? 'shop'}`,
    (signal) => ownerApi.analytics({ from: range.from, to: range.to, barberId }, signal),
    { refreshMs: LIVE_REFRESH_MS },
  );
  const data = analytics.data;

  return (
    <div className="container container--wide biz-page" data-testid="analytics-page">
      <PageHeader title="Analytics" lead="How the shop is doing, live: for the whole shop or one barber.">
        <Live updatedAt={analytics.updatedAt} loading={analytics.status === 'loading'} zone={zone} />
      </PageHeader>

      {catalog ? (
        <div className="biz-analytics-controls">
          <Scope catalog={catalog} barberId={barberId} onChange={(id) => update({ barber: id })} />
          <Periods
            kind={kind}
            onChange={(next) => update({ period: next === 'today' ? null : next, from: null, to: null })}
            onCustom={() => setCustomOpen(true)}
            customLabel={kind === 'custom' ? rangeLabel(range, today) : null}
          />
        </div>
      ) : null}
      <p className="biz-period-line" data-testid="period-line">
        <strong>{periodTitle(kind, range, today)}</strong>
        {kind !== 'custom' ? `: ${rangeLabel(range, today)}` : ''}
        {barberId ? ` · ${catalog?.barbers.find((b) => b.id === barberId)?.name}` : ' · Whole shop'}
      </p>

      {analytics.status === 'error' ? (
        <ErrorBanner
          title={data ? "Couldn't refresh" : "Couldn't load the numbers"}
          message={data ? `${analytics.error} Showing the numbers from before.` : analytics.error}
          onRetry={analytics.reload}
        />
      ) : null}

      {data ? (
        <div className="biz-analytics-grid">
          <TotalSales data={data} range={range} today={today} isToday={kind === 'today'} />
          <TopBarber data={data} />
          {kind === 'today' ? (
            <TodayByBarber data={data} />
          ) : (
            <section className="biz-card biz-wide-card" aria-labelledby="daily-title" data-testid="daily-sales">
              <h2 id="daily-title" className="biz-card__title">
                {data.granularity === 'month' ? 'Sales by month' : 'Daily sales'}
              </h2>
              <ChartFrame title={data.granularity === 'month' ? 'sales by month' : 'daily sales'} table={<DailyTable series={data.series} />}>
                <DailyChart series={data.series} />
              </ChartFrame>
            </section>
          )}
          <Leaderboard data={data} selected={barberId} />
          <TopServices data={data} />
          <ProductsSold data={data} />
          <Productivity data={data} />
        </div>
      ) : analytics.status !== 'error' ? (
        <Loading />
      ) : null}

      {customOpen ? (
        <CustomDialog
          open
          initial={range}
          today={today}
          onClose={() => setCustomOpen(false)}
          onApply={(chosen) => {
            setCustomOpen(false);
            update({ period: 'custom', from: chosen.from, to: chosen.to });
          }}
        />
      ) : null}
    </div>
  );
}
