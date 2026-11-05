// "Today's sales" (or another day's): time, client, barber, how they paid and the total,
// newest first. A voided sale is struck through and says why. Void asks first, with an
// optional reason, and for a card sale says to refund the card in the Stripe Dashboard.

import { useState } from 'react';
import { errorMessage } from '../../../api/errors';
import { Dialog } from '../../../components/Dialog';
import { Icon } from '../../../components/Icon';
import { money } from '../../../lib/format';
import { timeLabel } from '../../../lib/shopTime';
import { ownerApi } from '../../api/client';
import { SuccessLine } from '../../components/common';
import { methodTitle } from '../../lib/fees';
import { moneyWithCommas } from '../../lib/money';
import type { Sale, SalesDay, VoidedSale } from '../../types';

/** "Haircut, 2 × Sample pomade". */
export function itemsSummary(sale: Pick<Sale, 'items'>): string {
  return sale.items.map((item) => `${item.quantity > 1 ? `${item.quantity} × ` : ''}${item.name}`).join(', ');
}

/** Void a sale: the question, an optional reason, and the answer. */
export function useVoidSale(onVoided: (result: VoidedSale) => void) {
  const [sale, setSale] = useState<Sale | null>(null);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [zone, setZone] = useState('America/Los_Angeles');

  const ask = (target: Sale, timeZone: string) => {
    setSale(target);
    setZone(timeZone);
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
            {sale.customerName ?? 'Walk-in'}: {itemsSummary(sale)}, sold by {sale.barberName} at {timeLabel(new Date(sale.soldAt), zone)}. Once it's voided it
            no longer counts in your sales.{sale.appointmentId ? ' The appointment stays done, and can be checked out again.' : ''}
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
  title,
  zone,
  onVoid,
  onNewSale,
  message,
}: {
  day: SalesDay | null;
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
              ? 'Loading…'
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
                  <span className={voided ? 'biz-struck' : undefined}>{money(sale.totalCents)}</span>
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
                      aria-label={`Void the ${money(sale.totalCents)} sale to ${sale.customerName ?? 'a walk-in'}`}
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
