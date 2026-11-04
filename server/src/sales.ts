import { z } from 'zod';
import { appMadeKey, hashManageToken, requireOwner } from './auth.js';
import type { Catalog } from './catalog.js';
import { pgConstraint, pgErrorCode, UNIQUE_VIOLATION, type Queryable } from './db.js';
import type { Deps } from './deps.js';
import { ApiError, json, readJsonObject } from './http.js';
import type { Context } from './router.js';
import type { AppointmentRow, SaleMethod } from './serialize.js';
import { dayBounds, formatInstant, localDate } from './time.js';
import { calendarDate, charLength, optionalText, parse, personName, shortId, UUID_RE } from './validation.js';

// Sales: what the shop sells at checkout, for the barber who gets credit, with or
// without an appointment. A sale has one or more items (a catalog service, one of
// the shop's products, or a custom item such as a gift card) and is paid in cash,
// another way the shop only records (Zelle, Cash App…), or by card with Tap to
// Pay. Cash and other sales are recorded here (POST /api/owner/sales); a card
// sale's ticket travels with its payment (POST /api/owner/payments with `sale`)
// and is recorded once that payment succeeds (recordCardSale). Names and prices
// are copied onto each item when it's sold. A sale is never edited: a mistake is
// voided, and a voided sale no longer counts. Analytics are built from live sales
// (analytics.ts).

export const MAX_SALE_ITEMS = 20;
export const MAX_QUANTITY = 99;
export const MAX_SALE_CENTS = 1_000_000;

const PRICE_MESSAGE = 'Prices must be whole cents, from $0 to $10,000.';
const QUANTITY_MESSAGE = `The quantity must be a whole number from 1 to ${MAX_QUANTITY}.`;
const CONTROL_CHARS = /[\u0000-\u001f\u007f-\u009f\u2028\u2029]/;

const unitCents = z
  .number({ error: PRICE_MESSAGE })
  .int({ error: PRICE_MESSAGE })
  .min(0, { error: PRICE_MESSAGE })
  .max(MAX_SALE_CENTS, { error: PRICE_MESSAGE });

const quantity = z
  .number({ error: QUANTITY_MESSAGE })
  .int({ error: QUANTITY_MESSAGE })
  .min(1, { error: QUANTITY_MESSAGE })
  .max(MAX_QUANTITY, { error: QUANTITY_MESSAGE });

/** A uuid, lowercased the way Postgres prints it; anything else is left for the lookup to turn down. */
const uuidText = (message: string) =>
  z.string({ error: message }).transform((v) => (UUID_RE.test(v.trim()) ? v.trim().toLowerCase() : v));

const itemName = z
  .string({ error: 'Give the item a name, like Gift card.' })
  .trim()
  .refine((v) => v.length > 0, { error: 'Give the item a name, like Gift card.' })
  .refine((v) => charLength(v) <= 80, { error: 'Keep the item name to 80 characters or fewer.' })
  .refine((v) => !CONTROL_CHARS.test(v), { error: 'The item name has characters we can’t use.' });

const saleItem = z.discriminatedUnion(
  'kind',
  [
    z.object({
      kind: z.literal('service'),
      serviceId: shortId,
      unitCents: unitCents.nullish(),
      quantity: quantity.nullish(),
    }),
    z.object({
      kind: z.literal('product'),
      productId: uuidText('Each product needs its productId.'),
      unitCents: unitCents.nullish(),
      quantity: quantity.nullish(),
    }),
    z.object({
      kind: z.literal('custom'),
      name: itemName,
      unitCents: z
        .number({ error: 'Enter the price of each custom item.' })
        .int({ error: PRICE_MESSAGE })
        .min(0, { error: PRICE_MESSAGE })
        .max(MAX_SALE_CENTS, { error: PRICE_MESSAGE }),
      quantity: quantity.nullish(),
    }),
  ],
  { error: 'Each item needs a kind: service, product or custom.' },
);

type SaleItemInput = z.output<typeof saleItem>;

/** The client's name on the sale, or null; an empty one counts as none. */
const customerName = z.preprocess((v) => (typeof v === 'string' && v.trim() === '' ? null : v), personName.nullish());

const ticketFields = {
  barberId: shortId.nullish(),
  appointmentId: uuidText('appointmentId must be an appointment id.').nullish(),
  customerName,
  items: z
    .array(saleItem, { error: 'Send the items as a list.' })
    .min(1, { error: 'Add at least one item.' })
    .max(MAX_SALE_ITEMS, { error: `A sale can have at most ${MAX_SALE_ITEMS} items.` }),
};

export const CARD_SALE_MESSAGE = 'Take card payments with Tap to Pay in the app. The sale is saved when the payment goes through.';

// POST /api/owner/sales: a cash or other sale.
const saleBody = z.object({
  ...ticketFields,
  method: z
    .enum(['cash', 'other', 'card'], { error: 'method must be cash or other.' })
    .refine((m) => m !== 'card', { error: CARD_SALE_MESSAGE }),
});

type SaleBody = z.output<typeof saleBody>;

/** A card checkout's ticket, sent as `sale` with POST /api/owner/payments. */
export const cardSaleBody = z.object(ticketFields, { error: 'sale must be the ticket: the barber and the items.' });

export type CardSaleInput = z.output<typeof cardSaleBody>;

type TicketInput = Pick<SaleBody, 'barberId' | 'appointmentId' | 'customerName' | 'items'>;

export type SaleItemKind = 'service' | 'product' | 'custom';

/** One item as it's recorded: what it is, its name and price when sold, and its total. */
export interface DraftItem {
  kind: SaleItemKind;
  serviceId: string | null;
  productId: string | null;
  name: string;
  quantity: number;
  unitCents: number;
  totalCents: number;
}

/** A ticket as it's recorded: who gets credit, with names and prices filled in, and the total. */
export interface SaleDraft {
  barberId: string;
  appointmentId: string | null;
  customerName: string | null;
  items: DraftItem[];
  totalCents: number;
}

const appointmentNotFound = () => new ApiError('not_found', "We couldn't find that appointment.");
const productNotFound = () => new ApiError('not_found', "We couldn't find that product. It may have been deleted.");

/**
 * Whether `appointment` can be checked out: booked or completed, and not checked out
 * already (its live sale, copied onto the row). Otherwise the 409 that says why.
 */
function checkoutProblem(appointment: AppointmentRow): ApiError | null {
  if (appointment.status === 'cancelled') {
    return new ApiError(
      'not_checkoutable',
      "This appointment was cancelled, so it can't be checked out. Reopen it first, or check out without the appointment.",
    );
  }
  if (appointment.status === 'no_show') {
    return new ApiError(
      'not_checkoutable',
      "This appointment was marked a no-show, so it can't be checked out. Reopen it first, or check out without the appointment.",
    );
  }
  if (appointment.sale_id !== null) return new ApiError('already_checked_out', 'This appointment was already checked out.');
  return null;
}

/** The barber's price for a service on the menu: their one price for it, or a 400 asking for the price. */
function menuPrice(catalog: Catalog, barberId: string, barberName: string, serviceId: string, serviceName: string): number {
  const prices = [
    ...new Set(catalog.data.offerings.filter((o) => o.barberId === barberId && o.serviceId === serviceId).map((o) => o.priceCents)),
  ];
  if (prices.length === 1 && prices[0] !== undefined) return prices[0];
  if (prices.length === 0) throw new ApiError('invalid_request', `${barberName} doesn't offer ${serviceName}. Enter the price.`);
  throw new ApiError('invalid_request', `${barberName} has more than one price for ${serviceName}. Enter the price.`);
}

/**
 * Checks a ticket and fills it in, the same way for cash, other and card sales:
 *  - an appointment must exist and be booked or completed, with no live sale (409
 *    not_checkoutable or already_checked_out); `lock` locks its row for the checkout;
 *  - the barber who gets credit defaults to the appointment's and must be on the team,
 *    and the client's name defaults to the appointment's;
 *  - a service must be on the menu (or be the appointment's own); its price defaults to the
 *    appointment's price for the appointment's service, otherwise to the barber's price for it,
 *    and must be entered when the barber doesn't offer it or has more than one price;
 *  - a product must exist (it may be hidden); its price defaults to the product's, and must be
 *    entered when the product has none;
 *  - quantities default to 1, and the total (0 to $10,000) is the sum of the items.
 */
async function draftTicket(
  db: Queryable,
  catalog: Catalog,
  input: TicketInput,
  lock: boolean,
): Promise<{ draft: SaleDraft; appointment: AppointmentRow | null }> {
  let appointment: AppointmentRow | null = null;
  if (input.appointmentId != null) {
    if (!UUID_RE.test(input.appointmentId)) throw appointmentNotFound();
    const { rows } = await db.query<AppointmentRow>(`SELECT * FROM appointments WHERE id = $1${lock ? ' FOR UPDATE' : ''}`, [
      input.appointmentId,
    ]);
    appointment = rows[0] ?? null;
    if (!appointment) throw appointmentNotFound();
    const problem = checkoutProblem(appointment);
    if (problem) throw problem;
  }

  const barberId = input.barberId ?? appointment?.barber_id;
  if (!barberId) throw new ApiError('invalid_request', 'Pick the barber who gets credit for this sale.');
  const { rows: barbers } = await db.query<{ name: string; active: boolean }>('SELECT name, active FROM barbers WHERE id = $1', [barberId]);
  const barber = barbers[0];
  if (!barber?.active) throw new ApiError('invalid_request', "That barber isn't on the team. Pick who did the service.");

  const productIds = [...new Set(input.items.flatMap((item) => (item.kind === 'product' ? [item.productId] : [])))];
  if (productIds.some((id) => !UUID_RE.test(id))) throw productNotFound();
  const products = new Map<string, { name: string; price_cents: number | null }>();
  if (productIds.length > 0) {
    const { rows } = await db.query<{ id: string; name: string; price_cents: number | null }>(
      'SELECT id, name, price_cents FROM products WHERE id = ANY($1::uuid[])',
      [productIds],
    );
    for (const row of rows) products.set(row.id, row);
  }

  const items = input.items.map((item: SaleItemInput): DraftItem => {
    const count = item.quantity ?? 1;
    const line = (fields: Omit<DraftItem, 'quantity' | 'totalCents'>): DraftItem => ({
      ...fields,
      quantity: count,
      totalCents: count * fields.unitCents,
    });
    if (item.kind === 'service') {
      const ownService = appointment !== null && item.serviceId === appointment.service_id;
      const name = catalog.service(item.serviceId)?.name ?? (ownService ? appointment?.service_name : undefined);
      if (!name) throw new ApiError('invalid_request', "That service isn't on the menu. Pick another, or add it as a custom item.");
      const price =
        item.unitCents ?? (ownService && appointment ? appointment.price_cents : menuPrice(catalog, barberId, barber.name, item.serviceId, name));
      return line({ kind: 'service', serviceId: item.serviceId, productId: null, name, unitCents: price });
    }
    if (item.kind === 'product') {
      const product = products.get(item.productId);
      if (!product) throw productNotFound();
      const price = item.unitCents ?? product.price_cents;
      if (price === null) throw new ApiError('invalid_request', `${product.name} has no price. Enter the price.`);
      return line({ kind: 'product', serviceId: null, productId: item.productId, name: product.name, unitCents: price });
    }
    return line({ kind: 'custom', serviceId: null, productId: null, name: item.name, unitCents: item.unitCents });
  });

  const totalCents = items.reduce((sum, item) => sum + item.totalCents, 0);
  if (totalCents > MAX_SALE_CENTS) throw new ApiError('invalid_request', 'A sale can be at most $10,000. Split it into two sales.');
  return {
    draft: {
      barberId,
      appointmentId: appointment?.id ?? null,
      customerName: input.customerName ?? appointment?.customer_name ?? null,
      items,
      totalCents,
    },
    appointment,
  };
}

/**
 * Records a sale and its items in the caller's transaction. With `appointment` (locked by the
 * caller and checked out by this sale), the appointment becomes completed and keeps the sale on
 * its row; it's marked paid with the sale's total unless succeeded card payments already paid
 * it (then the card numbers stay). A product deleted in the meantime is recorded by name only.
 */
async function insertSale(
  tx: Queryable,
  deps: Pick<Deps, 'uuid'>,
  draft: SaleDraft,
  options: { method: SaleMethod; paymentIntentId: string | null; soldAt: Date; idempotencyKey: string | undefined; appointment: AppointmentRow | null },
): Promise<string> {
  const id = deps.uuid();
  const appointmentId = options.appointment?.id ?? null;
  await tx.query(
    `INSERT INTO sales (id, barber_id, appointment_id, customer_name, method, payment_intent_id, total_cents, sold_at,
                        idempotency_key_hash, created_at, updated_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $8, $8)`,
    [
      id,
      draft.barberId,
      appointmentId,
      draft.customerName,
      options.method,
      options.paymentIntentId,
      draft.totalCents,
      options.soldAt,
      options.idempotencyKey ? hashManageToken(options.idempotencyKey) : null,
    ],
  );
  const items = draft.items.map((item, position) => ({
    id: deps.uuid(),
    position,
    kind: item.kind,
    service_id: item.serviceId,
    product_id: item.productId,
    name: item.name,
    quantity: item.quantity,
    unit_cents: item.unitCents,
    total_cents: item.totalCents,
  }));
  await tx.query(
    `INSERT INTO sale_items (id, sale_id, position, kind, service_id, product_id, name, quantity, unit_cents, total_cents)
     SELECT i.id, $1, i.position, i.kind, i.service_id, p.id, i.name, i.quantity, i.unit_cents, i.total_cents
       FROM jsonb_to_recordset($2::jsonb)
            AS i(id uuid, position integer, kind text, service_id text, product_id uuid, name text, quantity integer, unit_cents integer, total_cents integer)
       LEFT JOIN products p ON p.id = i.product_id`,
    [id, JSON.stringify(items)],
  );
  if (appointmentId !== null) {
    await tx.query(
      `UPDATE appointments a
          SET status = 'completed',
              sale_id = $2, sale_total_cents = $3, sale_method = $4,
              payment_status = CASE WHEN card.paid THEN a.payment_status ELSE 'paid' END,
              paid_cents = CASE WHEN card.paid THEN a.paid_cents ELSE $3 END,
              paid_at = CASE WHEN card.paid THEN a.paid_at ELSE $5 END,
              updated_at = $5
         FROM (SELECT EXISTS (SELECT 1 FROM payments
                               WHERE appointment_id = $1 AND status = 'succeeded' AND kind = 'in_person') AS paid) card
        WHERE a.id = $1`,
      [appointmentId, id, draft.totalCents, options.method, options.soldAt],
    );
  }
  return id;
}

// Reading sales back, as the API's Sale JSON.

interface SaleRow {
  id: string;
  barber_id: string;
  barber_name: string;
  appointment_id: string | null;
  customer_name: string | null;
  method: SaleMethod;
  payment_intent_id: string | null;
  total_cents: number;
  sold_at: Date;
  voided_at: Date | null;
  void_reason: string | null;
}

interface SaleItemRow {
  sale_id: string;
  kind: SaleItemKind;
  service_id: string | null;
  product_id: string | null;
  name: string;
  quantity: number;
  unit_cents: number;
  total_cents: number;
}

interface LoadedSale {
  row: SaleRow;
  items: SaleItemRow[];
}

const SALE_COLUMNS = `s.id, s.barber_id, b.name AS barber_name, s.appointment_id, s.customer_name, s.method, s.payment_intent_id,
  s.total_cents, s.sold_at, s.voided_at, s.void_reason`;

/** Sales matching `where` (on `sales s`), in `order`, with their items: two queries in all. */
async function loadSales(db: Queryable, where: string, values: unknown[], order = 's.sold_at DESC, s.id DESC'): Promise<LoadedSale[]> {
  const { rows } = await db.query<SaleRow>(`SELECT ${SALE_COLUMNS} FROM sales s JOIN barbers b ON b.id = s.barber_id WHERE ${where} ORDER BY ${order}`, values);
  if (rows.length === 0) return [];
  const { rows: items } = await db.query<SaleItemRow>(
    `SELECT sale_id, kind, service_id, product_id, name, quantity, unit_cents, total_cents
       FROM sale_items WHERE sale_id = ANY($1::uuid[]) ORDER BY sale_id, position`,
    [rows.map((r) => r.id)],
  );
  const bySale = new Map<string, SaleItemRow[]>();
  for (const item of items) {
    const list = bySale.get(item.sale_id);
    if (list) list.push(item);
    else bySale.set(item.sale_id, [item]);
  }
  return rows.map((row) => ({ row, items: bySale.get(row.id) ?? [] }));
}

async function loadSale(db: Queryable, id: string): Promise<LoadedSale | null> {
  return (await loadSales(db, 's.id = $1', [id]))[0] ?? null;
}

export function saleJSON({ row, items }: LoadedSale) {
  return {
    id: row.id,
    barberId: row.barber_id,
    barberName: row.barber_name,
    appointmentId: row.appointment_id,
    customerName: row.customer_name,
    /** "cash", "other" (recorded only: Zelle, Cash App…) or "card" (Tap to Pay). */
    method: row.method,
    /** The Tap to Pay payment of a card sale (a payments id), else null. */
    paymentIntentId: row.payment_intent_id,
    totalCents: row.total_cents,
    items: items.map((item) => ({
      kind: item.kind,
      serviceId: item.service_id,
      /** Null for a product that was deleted since; the name stays. */
      productId: item.product_id,
      name: item.name,
      quantity: item.quantity,
      unitCents: item.unit_cents,
      totalCents: item.total_cents,
    })),
    soldAt: formatInstant(row.sold_at),
    voidedAt: row.voided_at ? formatInstant(row.voided_at) : null,
    voidReason: row.void_reason,
  };
}

// POST /api/owner/sales (optional Idempotency-Key, like shop bookings)

const keyUsed = () => new ApiError('invalid_request', 'That sale key was already used for another sale.');

/** The unique index on `sales.idempotency_key_hash` (migrations/006). */
const IDEMPOTENCY_KEY_INDEX = 'sales_idempotency_key_hash_key';
/** The unique index that allows one live sale per appointment (migrations/006). */
const LIVE_APPOINTMENT_INDEX = 'sales_live_appointment_key';

/**
 * Whether `sale` is the sale `body` asks for: the same method and appointment, the same
 * barber and client when the body names them, and the same items in the same order (kind,
 * service or product, quantity, and the price when the body gives one).
 */
function sameSale({ row, items }: LoadedSale, body: SaleBody): boolean {
  if (row.method !== body.method || row.appointment_id !== (body.appointmentId ?? null)) return false;
  if (body.barberId != null && body.barberId !== row.barber_id) return false;
  if (body.customerName != null && body.customerName !== row.customer_name) return false;
  if (items.length !== body.items.length) return false;
  return body.items.every((item, i) => {
    const stored = items[i];
    if (!stored || stored.kind !== item.kind || stored.quantity !== (item.quantity ?? 1)) return false;
    if (item.unitCents != null && item.unitCents !== stored.unit_cents) return false;
    if (item.kind === 'service') return stored.service_id === item.serviceId;
    // A product deleted since keeps only its name.
    if (item.kind === 'product') return stored.product_id === null || stored.product_id === item.productId;
    return stored.name === item.name;
  });
}

/** The sale that key already recorded, as it is now (200); null if the key is new; a 400 if it recorded another. */
async function saleReplay(db: Queryable, key: string, body: SaleBody): Promise<Response | null> {
  const { rows } = await db.query<{ id: string }>('SELECT id FROM sales WHERE idempotency_key_hash = $1', [hashManageToken(key)]);
  const sale = rows[0] ? await loadSale(db, rows[0].id) : null;
  if (!sale) return null;
  if (!sameSale(sale, body)) throw keyUsed();
  return json({ sale: saleJSON(sale) });
}

export async function postSale(ctx: Context): Promise<Response> {
  requireOwner(ctx.request, ctx.deps.config);
  // The owner app's key for this checkout, so Save again after a lost answer can't record it twice.
  const key = appMadeKey(ctx.request, 'Idempotency-Key');
  const body = parse(saleBody, await readJsonObject(ctx.request));
  // A retry is answered first: its appointment is already checked out (by this very sale).
  if (key) {
    const replayed = await saleReplay(ctx.deps.db, key, body);
    if (replayed) return replayed;
  }
  const method = body.method === 'other' ? 'other' : 'cash';
  const now = ctx.deps.now();
  try {
    const id = await ctx.deps.db.transaction(async (tx) => {
      // The appointment's row stays locked until the sale is in, so two checkouts can't both take it.
      const { draft, appointment } = await draftTicket(tx, ctx.deps.catalog, body, true);
      return insertSale(tx, ctx.deps, draft, { method, paymentIntentId: null, soldAt: now, idempotencyKey: key, appointment });
    });
    const sale = await loadSale(ctx.deps.db, id);
    if (!sale) throw new Error('A sale just recorded is missing');
    return json({ sale: saleJSON(sale) }, 201);
  } catch (error) {
    // Another copy of this request may have recorded it meanwhile: answer like a retry.
    if (key) {
      const replayed = await saleReplay(ctx.deps.db, key, body);
      if (replayed) return replayed;
      if (pgErrorCode(error) === UNIQUE_VIOLATION && pgConstraint(error) === IDEMPOTENCY_KEY_INDEX) throw keyUsed();
    }
    if (pgErrorCode(error) === UNIQUE_VIOLATION && pgConstraint(error) === LIVE_APPOINTMENT_INDEX) {
      throw new ApiError('already_checked_out', 'This appointment was already checked out.');
    }
    throw error;
  }
}

// GET /api/owner/sales?date=YYYY-MM-DD: the shop-local day's sales, newest first, voided ones too.

const dayQuery = z.object({ date: calendarDate.optional() });

export async function listSales(ctx: Context): Promise<Response> {
  requireOwner(ctx.request, ctx.deps.config);
  const zone = ctx.deps.catalog.timeZone;
  const date = parse(dayQuery, Object.fromEntries(ctx.url.searchParams)).date ?? localDate(ctx.deps.now(), zone);
  const { start, end } = dayBounds(date, zone);
  const sales = await loadSales(ctx.deps.db, 's.sold_at >= $1 AND s.sold_at < $2', [start, end]);
  const live = sales.filter((sale) => sale.row.voided_at === null);
  return json({
    date,
    sales: sales.map(saleJSON),
    // Voided sales don't count.
    totals: { totalCents: live.reduce((sum, sale) => sum + sale.row.total_cents, 0), count: live.length },
  });
}

// POST /api/owner/sales/:id/void { reason? }: idempotent; voiding again answers the same.

const voidBody = z.object({ reason: optionalText(200, 'Keep the reason to 200 characters or fewer.', 'reason') });

const VOIDED_MESSAGE = 'The sale was voided, so it no longer counts in your sales.';
const VOIDED_CARD_MESSAGE = `${VOIDED_MESSAGE} Voiding doesn't refund the card: refunds are made in the Stripe Dashboard.`;

/**
 * Voids a sale: it stops counting, and its appointment (which stays completed) can be checked
 * out again. A cash or other sale's appointment is unpaid again, unless succeeded card payments
 * paid it. Voiding a card sale doesn't refund the card; refunds are made in the Stripe Dashboard.
 */
export async function voidSale(ctx: Context): Promise<Response> {
  requireOwner(ctx.request, ctx.deps.config);
  const notFound = () => new ApiError('not_found', "We couldn't find that sale.");
  const id = (ctx.params.id ?? '').toLowerCase();
  if (!UUID_RE.test(id)) throw notFound();
  const { reason } = parse(voidBody, await readJsonObject(ctx.request));
  const now = ctx.deps.now();
  await ctx.deps.db.transaction(async (tx) => {
    const { rows } = await tx.query<{ appointment_id: string | null; voided_at: Date | null }>(
      'SELECT appointment_id, voided_at FROM sales WHERE id = $1 FOR UPDATE',
      [id],
    );
    const sale = rows[0];
    if (!sale) throw notFound();
    if (sale.voided_at !== null) return;
    await tx.query('UPDATE sales SET voided_at = $2, void_reason = $3, updated_at = $2 WHERE id = $1', [id, now, reason]);
    if (sale.appointment_id !== null) {
      await tx.query(
        `UPDATE appointments a
            SET sale_id = NULL, sale_total_cents = NULL, sale_method = NULL,
                payment_status = CASE WHEN card.paid THEN a.payment_status ELSE 'unpaid' END,
                paid_cents = CASE WHEN card.paid THEN a.paid_cents ELSE NULL END,
                paid_at = CASE WHEN card.paid THEN a.paid_at ELSE NULL END,
                updated_at = $3
           FROM (SELECT EXISTS (SELECT 1 FROM payments
                                 WHERE appointment_id = $1 AND status = 'succeeded' AND kind = 'in_person') AS paid) card
          WHERE a.id = $1 AND a.sale_id = $2`,
        [sale.appointment_id, id, now],
      );
    }
  });
  const sale = await loadSale(ctx.deps.db, id);
  if (!sale) throw notFound();
  return json({ sale: saleJSON(sale), message: sale.row.method === 'card' ? VOIDED_CARD_MESSAGE : VOIDED_MESSAGE });
}

// Card sales: the ticket travels with the payment (payments.ts) and is recorded when it succeeds.

/**
 * The ticket of a card checkout (POST /api/owner/payments with `sale`), checked and filled in
 * exactly like a cash sale's, to keep with the payment until it succeeds. The payment's amount
 * must be the ticket's total (400 amount_mismatch). A top-level appointmentId must be the
 * ticket's, and stands for it when the ticket names none.
 */
export async function cardSaleDraft(
  db: Queryable,
  catalog: Catalog,
  sale: CardSaleInput,
  payment: { amountCents: number; appointmentId?: string | null | undefined },
): Promise<SaleDraft> {
  const topLevel = payment.appointmentId?.trim().toLowerCase() || null;
  const appointmentId = sale.appointmentId === undefined ? topLevel : sale.appointmentId;
  if (topLevel !== null && appointmentId !== topLevel) {
    throw new ApiError('invalid_request', "The appointment doesn't match the sale's appointment.");
  }
  const { draft } = await draftTicket(db, catalog, { ...sale, appointmentId }, false);
  if (draft.totalCents !== payment.amountCents) throw new ApiError('amount_mismatch', "The amount doesn't match the items.");
  return draft;
}

/**
 * A ticket as stored in payments.sale_draft, read back defensively (it's JSON in the database).
 * It was checked when it was stored; this only makes sure it's still a ticket. Lengths count
 * characters as people do (an emoji is one), like the checks it passed.
 */
const storedDraft = z.object({
  barberId: z.string().min(1),
  appointmentId: z.string().regex(UUID_RE).nullable(),
  customerName: z
    .string()
    .refine((v) => charLength(v) >= 1 && charLength(v) <= 60)
    .nullable(),
  items: z
    .array(
      z.object({
        kind: z.enum(['service', 'product', 'custom']),
        serviceId: z.string().min(1).nullable(),
        productId: z.string().regex(UUID_RE).nullable(),
        name: z.string().min(1),
        quantity: z.number().int().min(1).max(MAX_QUANTITY),
        unitCents: z.number().int().min(0).max(MAX_SALE_CENTS),
        totalCents: z.number().int().min(0),
      }),
    )
    .min(1)
    .max(MAX_SALE_ITEMS),
  totalCents: z.number().int().min(0).max(MAX_SALE_CENTS),
});

/**
 * Records a card checkout's sale once its payment succeeded. syncPayment calls it in the
 * transaction that marks the payment succeeded (the …/complete call or Stripe's webhook,
 * whichever comes first): the payment row is locked and a payment has at most one sale, so it
 * happens exactly once. The sale is sold at `now`. If its appointment can't take it any more
 * (another sale checked it out meanwhile, or it was cancelled or marked a no-show), the sale is
 * recorded without the appointment, so the money still counts, the payment lets go of the
 * appointment too, and that's logged. Returns the sale's id, or null when the payment has no
 * ticket (or isn't a succeeded in-person payment).
 */
export async function recordCardSale(tx: Queryable, deps: Pick<Deps, 'uuid' | 'log'>, paymentId: string, now: Date): Promise<string | null> {
  // Locked, then checked again: a …/complete and a webhook for the same payment take turns here,
  // and the second finds the first one's sale.
  const { rows } = await tx.query<{ status: string; kind: string; sale_draft: unknown }>(
    'SELECT status, kind, sale_draft FROM payments WHERE id = $1 FOR UPDATE',
    [paymentId],
  );
  const payment = rows[0];
  if (!payment || payment.status !== 'succeeded' || payment.kind !== 'in_person' || payment.sale_draft === null) return null;
  const { rows: recorded } = await tx.query<{ id: string }>('SELECT id FROM sales WHERE payment_intent_id = $1', [paymentId]);
  if (recorded[0]) return recorded[0].id;

  const parsed = storedDraft.safeParse(payment.sale_draft);
  if (!parsed.success) {
    deps.log.error("A card sale couldn't be recorded: its ticket is unreadable", { paymentId, problem: parsed.error.issues[0]?.message });
    return null;
  }
  const draft = parsed.data;
  let appointment: AppointmentRow | null = null;
  if (draft.appointmentId !== null) {
    const { rows: found } = await tx.query<AppointmentRow>('SELECT * FROM appointments WHERE id = $1 FOR UPDATE', [draft.appointmentId]);
    const row = found[0];
    if (row && !checkoutProblem(row)) {
      appointment = row;
    } else {
      // The payment no longer stands for that appointment either, so it doesn't mark it paid
      // (it may have been paid another way): the money counts as a sale of its own.
      await tx.query('UPDATE payments SET appointment_id = NULL, updated_at = $2 WHERE id = $1', [paymentId, now]);
      deps.log.warn('A card sale was recorded without its appointment, which was already checked out, cancelled or a no-show', {
        paymentId,
        appointmentId: draft.appointmentId,
        status: row?.status ?? null,
        liveSaleId: row?.sale_id ?? null,
      });
    }
  }
  return insertSale(
    tx,
    deps,
    { ...draft, appointmentId: appointment?.id ?? null },
    { method: 'card', paymentIntentId: paymentId, soldAt: now, idempotencyKey: undefined, appointment },
  );
}
