// "Today's sales" (or another day's): time, client, barber, how they paid and the total,
// newest first. A voided sale is struck through and says why. Void asks first, with an
// optional reason, and for a card sale says to refund the card in the Stripe Dashboard.

import { useState } from 'react';
import { errorMessage } from '../../../api/errors';
import { Dialog } from '../../../components/Dialog';
import { Icon } from '../../../components/Icon';
import { dateTimeLabel, localDate, timeLabel } from '../../../lib/shopTime';
import { ownerApi } from '../../api/client';
import { SuccessLine } from '../../components/common';
import { methodTitle } from '../../lib/fees';
import { moneyWithCommas } from '../../lib/money';
import type { Sale, SalesDay, VoidedSale } from '../../types';

/** "Haircut, 2 × Sample pomade". */
export function itemsSummary(sale: Pick<Sale, 'items'>): string {
  return sale.items.map((item) => `${item.quantity > 1 ? `${item.quantity} × ` : ''}${item.name}`).join(', ');
}

/**
 * The sale Void asks about: the sale itself, or (an appointment checked out on a day whose sales
 * couldn't be read) only what the appointment knows of it: its amount and how it was paid.
 */
export type SaleToVoid = Sale | Pick<Sale, 'id' | 'appointmentId' | 'customerName' | 'method' | 'totalCents'>;

function isWholeSale(sale: SaleToVoid): sale is Sale {
  return 'items' in sale;
}

/** "Luis Sample: Haircut, sold by Izzy at 12:30 PM." (with the day when it was sold on another one). */
function saleLine(sale: SaleToVoid, zone: string, day: string | null): string {
  const who = sale.customerName ?? 'Walk-in';
  if (!isWholeSale(sale)) return `${who}: a ${moneyWithCommas(sale.totalCents)} ${methodTitle(sale.method).toLowerCase()} sale.`;
  const soldAt = new Date(sale.soldAt);
  const when = day !== null && localDate(soldAt, zone) !== day ? `on ${dateTimeLabel(soldAt, zone)}` : `at ${timeLabel(soldAt, zone)}`;
  return `${who}: ${itemsSummary(sale)}, sold by ${sale.barberName} ${when}.`;
}

/** Void a sale: the question, an optional reason, and the answer. */
export function useVoidSale(onVoided: (result: VoidedSale) => void) {
  const [sale, setSale] = useState<SaleToVoid | null>(null);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [zone, setZone] = useState('America/Los_Angeles');
  const [day, setDay] = useState<string | null>(null);

  /** Asks about `target`; `shownDay` is the day on screen, so a sale from another day says when. */
  const ask = (target: SaleToVoid, timeZone: string, shownDay: string | null = null) => {
    setSale(target);
    setZone(timeZone);
    setDay(shownDay);
    setReason('');
    setError(null);
  };
  const close = () => {
    if (!busy) setSale(null);
  };
  const confirm = async () => {
    if (!sale) return;
    setBusy(true);
    setError(null);
    try {
      const result = await ownerApi.voidSale(sale.id, reason.trim() || null);
      setSale(null);
      onVoided(result);
    } catch (caught) {
      setError(errorMessage(caught));
    } finally {
      setBusy(false);
    }
  };

  const dialog = (
    <Dialog
      open={sale !== null}
      title={sale ? `Void this ${moneyWithCommas(sale.totalCents)} sale?` : ''}
      onClose={close}
      testId="confirm-void"
      actions={
        <>
          <button type="button" className="button button--secondary" onClick={close} disabled={busy}>
            Keep the sale
          </button>
          <button type="button" className="button button--danger" onClick={() => void confirm()} disabled={busy}>
            {busy ? 'Voiding…' : 'Void sale'}
          </button>
        </>
      }
    >
      {sale ? (
        <>
          <p>
            {saleLine(sale, zone, day)} Once it's voided it no longer counts in your sales.
            {sale.appointmentId ? ' The appointment stays done, and can be checked out again.' : ''}
          </p>
          {sale.method === 'card' ? (
            <p className="biz-void-card">
              <strong>Refund the card in your Stripe Dashboard:</strong> voiding doesn't refund it.
            </p>
          ) : null}
          <div className="field">
            <label className="field__label" htmlFor="void-reason">
              Reason <span className="field__optional">(optional)</span>
            </label>
            <input
              id="void-reason"
              className="field__input"
              value={reason}
              maxLength={200}
              placeholder="Rang up twice"
              onChange={(e) => setReason(e.target.value)}
            />
          </div>
          {error ? (
            <p className="field__error" role="alert">
              <Icon name="error" />
              <span>{error}</span>
            </p>
          ) : null}
        </>
      ) : null}
    </Dialog>
  );
  return { ask, dialog };
}

export function SalesList({
  day,
  failed = false,
  title,
  zone,
  onVoid,
  onNewSale,
  message,
}: {
  day: SalesDay | null;
  /** The day didn't load (the page says so, with Try again): no "Loading…" here meanwhile. */
  failed?: boolean;
  title: string;
  zone: string;
  onVoid: (sale: Sale) => void;
  onNewSale: () => void;
  /** What the last void said. */
  message: string | null;
}) {
  return (
    <section className="biz-sales" aria-labelledby="sales-title" data-testid="sales">
      <div className="biz-sales__head">
        <div>
          <h2 id="sales-title" className="biz-sales__title">
            {title}
          </h2>
          <p className="secondary" data-testid="sales-totals">
            {day === null
              ? failed
                ? "Couldn't load the sales."
                : 'Loading…'
              : day.totals.count === 0
                ? day.sales.length > 0
                  ? "No sales yet. Voided sales don't count."
                  : 'No sales yet. They show here as you check clients out.'
                : `${day.totals.count} ${day.totals.count === 1 ? 'sale' : 'sales'} · ${moneyWithCommas(day.totals.totalCents)}`}
          </p>
        </div>
        <button type="button" className="button button--secondary" onClick={onNewSale}>
          New sale
        </button>
      </div>
      {message ? <SuccessLine testId="void-message">{message}</SuccessLine> : null}
      {day && day.sales.length > 0 ? (
        <ul className="biz-sales__list" role="list">
          {day.sales.map((sale) => {
            const voided = sale.voidedAt !== null;
            return (
              <li key={sale.id} className={`biz-sale${voided ? ' is-voided' : ''}`} data-testid="sale-row">
                <span className="biz-sale__time">{timeLabel(new Date(sale.soldAt), zone)}</span>
                <span className="biz-sale__who">
                  <span className="biz-sale__client">{sale.customerName ?? 'Walk-in'}</span>
                  <span className="biz-sale__items">{itemsSummary(sale)}</span>
                </span>
                <span className="biz-sale__barber">{sale.barberName}</span>
                <span className="biz-sale__method">{methodTitle(sale.method)}</span>
                {/* On a phone the columns above give way to one line under the client. */}
                <span className="biz-sale__meta">
                  {timeLabel(new Date(sale.soldAt), zone)} · {sale.barberName} · {methodTitle(sale.method)}
                </span>
                <span className="biz-sale__total">
                  {voided ? <span className="visually-hidden">Voided: </span> : null}
                  <span className={voided ? 'biz-struck' : undefined}>{moneyWithCommas(sale.totalCents)}</span>
                </span>
                <span className="biz-sale__action">
                  {voided ? (
                    <span className="biz-badge biz-badge--cancelled" title={sale.voidReason ?? undefined}>
                      Voided{sale.voidReason ? `: ${sale.voidReason}` : ''}
                    </span>
                  ) : (
                    <button
                      type="button"
                      className="text-button text-button--danger"
                      onClick={() => onVoid(sale)}
                      aria-label={`Void the ${moneyWithCommas(sale.totalCents)} sale to ${sale.customerName ?? 'a walk-in'}`}
                    >
                      Void
                    </button>
                  )}
                </span>
              </li>
            );
          })}
        </ul>
      ) : null}
    </section>
  );
}
