// "Check out", like the owner app's ticket: the client, Sold by, the items (+ Service, +
// Product, + Amount), the total, and how they're paying, cash or other (card payments
// happen on the iPhone with Tap to Pay). Recording asks first, with the amount; the
// receipt then says what happened: "Sold $60 · Cash · Izzy".

import { useMemo, useRef, useState } from 'react';
import { errorMessage, isApiError } from '../../../api/errors';
import type { Catalog } from '../../../api/types';
import { Dialog } from '../../../components/Dialog';
import { Icon } from '../../../components/Icon';
import { Monogram } from '../../../components/ui';
import { durationLabel, money } from '../../../lib/format';
import { dateTimeLabel } from '../../../lib/shopTime';
import { ownerApi } from '../../api/client';
import { ProductPlaceholder } from '../../components/common';
import { methodTitle } from '../../lib/fees';
import { moneyWithCommas, parseMoney } from '../../lib/money';
import {
  addAmount,
  addProduct,
  addService,
  lineTotal,
  removeLine,
  rememberBarber,
  SaleKeys,
  setBarber,
  setCustomerName,
  setPrice,
  setQuantity,
  ticketProblem,
  ticketTotal,
  newSale,
  MAX_QUANTITY,
  type Ticket,
} from '../../lib/ticket';
import type { Product, Sale } from '../../types';

type Adding = 'service' | 'product' | 'amount' | null;

function SoldBy({ ticket, catalog, onChange }: { ticket: Ticket; catalog: Catalog; onChange: (barberId: string) => void }) {
  return (
    <fieldset className="biz-chips">
      <legend className="biz-section-title">
        Sold by <span className="biz-required">(required)</span>
      </legend>
      <div className="biz-chips__list">
        {catalog.barbers.map((barber) => (
          <label key={barber.id} className="biz-chip">
            <input
              type="radio"
              name="sold-by"
              className="biz-chip__input"
              value={barber.id}
              checked={ticket.barberId === barber.id}
              onChange={() => onChange(barber.id)}
            />
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

function ServicePicker({ ticket, catalog, onPick }: { ticket: Ticket; catalog: Catalog; onPick: (offeringId: string) => void }) {
  if (!ticket.barberId) return <p className="biz-picker__empty">Pick who did the service first, under Sold by: each barber has his own prices.</p>;
  const barber = catalog.barbers.find((b) => b.id === ticket.barberId);
  const offerings = catalog.offerings.filter((o) => o.barberId === ticket.barberId);
  return (
    <div className="biz-picker" role="group" aria-label={`${barber?.name ?? 'This barber'}'s services`}>
      <p className="biz-picker__title">{barber?.name}'s services</p>
      <ul className="biz-picker__list" role="list">
        {offerings.map((offering) => {
          const name = catalog.services.find((s) => s.id === offering.serviceId)?.name ?? offering.serviceId;
          return (
            <li key={offering.id}>
              <button type="button" className="biz-picker__option" onClick={() => onPick(offering.id)}>
                <span className="biz-picker__name">{name}</span>
                <span className="biz-picker__detail">
                  {durationLabel(offering.durationMinutes)} · {offering.priceLabel}
                </span>
              </button>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

function ProductPicker({ products, onPick }: { products: Product[] | null; onPick: (product: Product) => void }) {
  if (products === null) return <p className="biz-picker__empty">Loading the products…</p>;
  if (products.length === 0) return <p className="biz-picker__empty">No products yet. Add them in Products, then sell them here.</p>;
  return (
    <div className="biz-picker" role="group" aria-label="Products">
      <p className="biz-picker__title">Products</p>
      <ul className="biz-picker__list biz-picker__list--products" role="list">
        {products.map((product) => (
          <li key={product.id}>
            <button type="button" className="biz-picker__option biz-picker__option--product" onClick={() => onPick(product)}>
              {product.imageUrl ? (
                <img className="biz-picker__photo" src={product.imageUrl} alt="" width={44} height={44} />
              ) : (
                <ProductPlaceholder className="biz-picker__photo biz-picker__photo--empty" />
              )}
              <span className="biz-picker__name">{product.name}</span>
              <span className="biz-picker__detail">{product.priceCents === null ? 'No price: you type it' : money(product.priceCents)}</span>
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}

function AmountForm({ onAdd }: { onAdd: (name: string, cents: number) => void }) {
  const [name, setName] = useState('');
  const [amount, setAmount] = useState('');
  const [error, setError] = useState<string | null>(null);
  const add = () => {
    const cents = parseMoney(amount);
    if (cents === null || cents <= 0) {
      setError('Type the amount, like 25 or 17.50.');
      return;
    }
    onAdd(name, cents);
  };
  return (
    <div className="biz-picker biz-amount" role="group" aria-label="Add an amount">
      <div className="biz-amount__fields">
        <div className="field">
          <label className="field__label" htmlFor="amount-name">
            Name <span className="field__optional">(optional)</span>
          </label>
          <input id="amount-name" className="field__input" value={name} placeholder="Other" maxLength={80} onChange={(e) => setName(e.target.value)} />
        </div>
        <div className="field">
          <label className="field__label" htmlFor="amount-value">
            Amount
          </label>
          <div className="biz-money-input">
            <span aria-hidden="true">$</span>
            <input
              id="amount-value"
              className="field__input"
              inputMode="decimal"
              value={amount}
              aria-invalid={error ? true : undefined}
              aria-describedby={error ? 'amount-error' : undefined}
              onChange={(e) => {
                setAmount(e.target.value);
                setError(null);
              }}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  e.preventDefault();
                  add();
                }
              }}
            />
          </div>
        </div>
      </div>
      {error ? (
        <p className="field__error" id="amount-error" role="alert">
          <Icon name="error" />
          <span>{error}</span>
        </p>
      ) : null}
      <button type="button" className="button button--secondary" onClick={add}>
        Add the amount
      </button>
    </div>
  );
}

function Lines({ ticket, products, onChange }: { ticket: Ticket; products: Product[] | null; onChange: (ticket: Ticket) => void }) {
  if (ticket.lines.length === 0) return <p className="biz-lines__empty">No items yet. Add a service, a product or an amount.</p>;
  return (
    <ul className="biz-lines" role="list">
      {ticket.lines.map((line) => {
        const product = line.kind === 'product' ? products?.find((p) => p.id === line.productId) : undefined;
        // Services ("From" prices vary), amounts, and a product with no price have a price to type.
        const editable = line.kind !== 'product' || product?.priceCents === null || line.priceText === '';
        const total = lineTotal(line);
        const priceId = `price-${line.key}`;
        return (
          <li key={line.key} className="biz-line">
            <div className="biz-line__main">
              <span className="biz-line__name">{line.name}</span>
              {editable ? (
                <span className="biz-line__price">
                  <label className="visually-hidden" htmlFor={priceId}>
                    Price of {line.name}
                  </label>
                  <span className="biz-money-input biz-money-input--small">
                    <span aria-hidden="true">$</span>
                    <input
                      id={priceId}
                      className="field__input"
                      inputMode="decimal"
                      value={line.priceText}
                      placeholder="Price"
                      aria-invalid={parseMoney(line.priceText) === null ? true : undefined}
                      onChange={(e) => onChange(setPrice(ticket, line.key, e.target.value))}
                    />
                  </span>
                </span>
              ) : (
                <span className="biz-line__unit">{money(parseMoney(line.priceText) ?? 0)} each</span>
              )}
            </div>
            <div className="biz-line__side">
              {line.kind === 'product' ? (
                <span className="biz-stepper" role="group" aria-label={`How many ${line.name}`}>
                  <button
                    type="button"
                    className="biz-stepper__button"
                    aria-label={`One fewer ${line.name}`}
                    disabled={line.quantity <= 1}
                    onClick={() => onChange(setQuantity(ticket, line.key, line.quantity - 1))}
                  >
                    −
                  </button>
                  <span className="biz-stepper__value" aria-live="polite">
                    {line.quantity}
                  </span>
                  <button
                    type="button"
                    className="biz-stepper__button"
                    aria-label={`One more ${line.name}`}
                    disabled={line.quantity >= MAX_QUANTITY}
                    onClick={() => onChange(setQuantity(ticket, line.key, line.quantity + 1))}
                  >
                    +
                  </button>
                </span>
              ) : null}
              <span className="biz-line__total">{total === null ? '—' : money(total)}</span>
              <button type="button" className="biz-line__remove" aria-label={`Remove ${line.name}`} onClick={() => onChange(removeLine(ticket, line.key))}>
                <Icon name="close" />
              </button>
            </div>
          </li>
        );
      })}
    </ul>
  );
}

export function Checkout({
  ticket,
  onChange,
  catalog,
  products,
  onSold,
}: {
  ticket: Ticket;
  onChange: (ticket: Ticket) => void;
  catalog: Catalog;
  /** The shop's products, null while loading. */
  products: Product[] | null;
  onSold: (sale: Sale) => void;
}) {
  const [adding, setAdding] = useState<Adding>(null);
  const [asking, setAsking] = useState<'cash' | 'other' | null>(null);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);
  const [failed, setFailed] = useState<string | null>(null);
  const keys = useRef(new SaleKeys());
  const total = ticketTotal(ticket);
  const barberName = useMemo(() => catalog.barbers.find((b) => b.id === ticket.barberId)?.name ?? null, [catalog, ticket.barberId]);
  const change = (next: Ticket) => {
    setProblem(null);
    setFailed(null);
    onChange(next);
  };

  const pay = (method: 'cash' | 'other') => {
    const wrong = ticketProblem(ticket);
    if (wrong) {
      setProblem(wrong);
      return;
    }
    setAsking(method);
  };

  const record = async () => {
    if (!asking) return;
    const sale = newSale(ticket, asking);
    setBusy(true);
    setFailed(null);
    try {
      const recorded = await ownerApi.createSale(sale, keys.current.keyFor(sale));
      keys.current.done();
      rememberBarber(recorded.barberId);
      setAsking(null);
      onSold(recorded);
    } catch (error) {
      setAsking(null);
      // After a lost answer the sale may have gone through: the same key makes trying again safe.
      setFailed(isApiError(error) && error.isOffline ? `${errorMessage(error)} Trying again is safe: the sale can't be recorded twice.` : errorMessage(error));
    } finally {
      setBusy(false);
    }
  };

  const totalText = total === null ? '—' : moneyWithCommas(total);
  const confirmTitle =
    asking === 'cash'
      ? `Record a ${totalText} cash sale for ${barberName ?? 'this barber'}?`
      : `Record a ${totalText} sale for ${barberName ?? 'this barber'}, paid another way?`;

  return (
    <div className="biz-checkout" data-testid="checkout">
      <section className="biz-checkout__client" aria-label="Client">
        {ticket.appointment ? (
          <div className="biz-client-card">
            <p className="biz-client-card__name">{ticket.appointment.customerName}</p>
            <p className="secondary">
              {ticket.appointment.serviceName} with {ticket.appointment.barberName} · {dateTimeLabel(new Date(ticket.appointment.start), catalog.timeZone)}
            </p>
          </div>
        ) : (
          <div className="field">
            <label className="field__label" htmlFor="walk-in-name">
              Walk-in <span className="field__optional">(name optional)</span>
            </label>
            <input
              id="walk-in-name"
              className="field__input"
              value={ticket.customerName}
              maxLength={60}
              autoComplete="off"
              onChange={(e) => change(setCustomerName(ticket, e.target.value))}
            />
          </div>
        )}
      </section>

      <p className="biz-note">
        <Icon name="info" className="biz-note__icon" />
        <span>Here you record cash and other payments. Card payments happen on the iPhone, with Tap to Pay in Izzy Clipz Business.</span>
      </p>

      <SoldBy ticket={ticket} catalog={catalog} onChange={(id) => change(setBarber(ticket, id))} />

      <section aria-labelledby="ticket-items">
        <h3 id="ticket-items" className="biz-section-title">
          Items
        </h3>
        <Lines ticket={ticket} products={products} onChange={change} />
        <div className="biz-add" role="group" aria-label="Add to the sale">
          {(['service', 'product', 'amount'] as const).map((kind) => (
            <button
              key={kind}
              type="button"
              className={`biz-add__button${adding === kind ? ' is-open' : ''}`}
              aria-expanded={adding === kind}
              onClick={() => setAdding(adding === kind ? null : kind)}
            >
              + {kind === 'service' ? 'Service' : kind === 'product' ? 'Product' : 'Amount'}
            </button>
          ))}
        </div>
        {adding === 'service' ? (
          <ServicePicker
            ticket={ticket}
            catalog={catalog}
            onPick={(offeringId) => {
              const offering = catalog.offerings.find((o) => o.id === offeringId);
              if (!offering) return;
              change(addService(ticket, offering, catalog.services.find((s) => s.id === offering.serviceId)?.name ?? offering.serviceId));
              setAdding(null);
            }}
          />
        ) : null}
        {adding === 'product' ? (
          <ProductPicker
            products={products}
            onPick={(product) => {
              change(addProduct(ticket, product));
              setAdding(null);
            }}
          />
        ) : null}
        {adding === 'amount' ? (
          <AmountForm
            onAdd={(name, cents) => {
              change(addAmount(ticket, name, cents));
              setAdding(null);
            }}
          />
        ) : null}
      </section>

      {/* The total and how they're paying stay at the bottom of the panel while the items scroll. */}
      <div className="biz-checkout__pay">
        <div className="biz-total" aria-live="polite">
          <span className="biz-total__label">Total</span>
          <span className="biz-total__value" data-testid="ticket-total">
            {totalText}
          </span>
        </div>

        <section aria-labelledby="ticket-paying">
          <h3 id="ticket-paying" className="biz-section-title">
            How are they paying?
          </h3>
          <div className="biz-pay">
            <button type="button" className="biz-pay__button" onClick={() => pay('cash')} disabled={busy}>
              <span className="biz-pay__title">Cash</span>
            </button>
            <button type="button" className="biz-pay__button" onClick={() => pay('other')} disabled={busy}>
              <span className="biz-pay__title">Other</span>
              <span className="biz-pay__subtitle">Squire, Zelle, Cash App…</span>
            </button>
          </div>
          {problem ? (
            <p className="field__error" role="alert" data-testid="ticket-problem">
              <Icon name="error" />
              <span>{problem}</span>
            </p>
          ) : null}
          {failed ? (
            <p className="field__error" role="alert" data-testid="ticket-failed">
              <Icon name="error" />
              <span>{failed}</span>
            </p>
          ) : null}
        </section>
      </div>

      <Dialog
        open={asking !== null}
        title={confirmTitle}
        onClose={() => (busy ? undefined : setAsking(null))}
        testId="confirm-sale"
        actions={
          <>
            <button type="button" className="button button--secondary" onClick={() => setAsking(null)} disabled={busy}>
              Not yet
            </button>
            <button type="button" className="button button--primary" onClick={() => void record()} disabled={busy}>
              {busy ? 'Recording…' : 'Record sale'}
            </button>
          </>
        }
      >
        <p>
          {ticket.lines.map((line) => `${line.quantity > 1 ? `${line.quantity} × ` : ''}${line.name}`).join(', ')}
          {ticket.appointment ? `, for ${ticket.appointment.customerName}` : ticket.customerName.trim() ? `, for ${ticket.customerName.trim()}` : ''}.
          {asking === 'other' ? ' Make sure the money came in (Squire, Zelle, Cash App…): this only records it.' : ''}
        </p>
      </Dialog>
    </div>
  );
}

/** The receipt: "Sold $60 · Cash · Izzy", the items, and Done. */
export function Receipt({ sale, zone }: { sale: Sale; zone: string }) {
  return (
    <div className="biz-receipt" data-testid="receipt">
      <Icon name="check" className="biz-receipt__icon" />
      <p className="biz-receipt__title" role="status">
        Sold {moneyWithCommas(sale.totalCents)} · {methodTitle(sale.method)} · {sale.barberName}
      </p>
      <p className="secondary">
        {sale.customerName ?? 'Walk-in'} · {dateTimeLabel(new Date(sale.soldAt), zone)}
      </p>
      <ul className="biz-receipt__items" role="list">
        {sale.items.map((item, index) => (
          <li key={index}>
            <span>
              {item.quantity > 1 ? `${item.quantity} × ` : ''}
              {item.name}
            </span>
            <span>{money(item.totalCents)}</span>
          </li>
        ))}
        <li className="biz-receipt__total">
          <span>Total</span>
          <span>{moneyWithCommas(sale.totalCents)}</span>
        </li>
      </ul>
    </div>
  );
}
