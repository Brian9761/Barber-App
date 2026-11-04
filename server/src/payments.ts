import Stripe from 'stripe';
import { z } from 'zod';
import { dayRange } from './appointments.js';
import { requireOwner } from './auth.js';
import type { Queryable } from './db.js';
import type { Deps } from './deps.js';
import { isFeeKind } from './feecase.js';
import { ApiError, json, readJsonObject, readText } from './http.js';
import type { Context } from './router.js';
import { syncNoShowFeeFromStripe } from './noshowfee.js';
import { cardSaleBody, cardSaleDraft, recordCardSale } from './sales.js';
import { PAYMENT_COLUMNS, paymentJSON, type PaymentRow } from './serialize.js';
import {
  currentConnection,
  requestOptions,
  shopStripe,
  stripeFailure,
  stripeMode,
  stripeOff,
  stripeSetup,
  type StripeErrorLike,
} from './stripeaccount.js';
import { accountDeauthorized, accountUpdated, connectionSummary, forgetTerminalLocation, terminalLocation } from './stripeconnect.js';
import { dayBounds } from './time.js';
import { charLength, email, parse, UUID_RE } from './validation.js';

// Moved to stripeaccount.ts with the shop's Stripe account; still importable from here.
export { stripeFailure, stripeMode, type StripeCall, type StripeErrorLike, type StripeMode } from './stripeaccount.js';

// In-person card payments with Stripe Terminal (Tap to Pay on iPhone). The
// server creates every PaymentIntent, so the app can't change the amount, and
// checks with Stripe before marking anything paid. With Stripe Connect they're
// direct charges on the shop's own connected account (stripeaccount.ts).

export const MIN_AMOUNT_CENTS = 50;
export const MAX_AMOUNT_CENTS = 100_000;

// GET /api/owner/me

export async function ownerMe(ctx: Context): Promise<Response> {
  await requireOwner(ctx);
  const { deps } = ctx;
  const setup = stripeSetup(deps.config);
  const connection = await currentConnection(deps);
  // `stripe` stays what older apps know: in connect mode, Stripe counts as set up once the shop's account can take card payments.
  const configured = setup === 'direct' || (setup === 'connect' && connection?.chargesEnabled === true);
  // The app needs the Terminal location to connect Tap to Pay (TapToPayConnectionConfiguration). In
  // connect mode it's the connected account's, made when the account was found able to take card
  // payments (stripeconnect.ts). All from the cache: this never asks Stripe.
  const locationId = setup === 'direct' ? (deps.config.stripeTerminalLocationId ?? null) : configured ? (connection?.locationId ?? null) : null;
  return json({
    ok: true,
    stripe: { configured, mode: configured ? stripeMode(deps.config) : null, locationId },
    connection: connectionSummary(setup, connection),
  });
}

/** Whether Stripe turned down a connection token's location (it doesn't exist on that account, or in that mode). */
function locationRefused(error: unknown): boolean {
  const e = (typeof error === 'object' && error !== null ? error : {}) as StripeErrorLike;
  return e.code === 'resource_missing' || e.statusCode === 404 || e.param === 'location';
}

// POST /api/owner/terminal/connection-token (the owner key only: Tap to Pay is iPhone-only)

export async function connectionToken(ctx: Context): Promise<Response> {
  await requireOwner(ctx, { keyOnly: true });
  const { deps } = ctx;
  const shop = await shopStripe(deps);
  const location = await terminalLocation(deps, shop);
  try {
    const token = await shop.stripe.terminal.connectionTokens.create(location ? { location } : {}, requestOptions(shop));
    return json({ secret: token.secret });
  } catch (error) {
    if (shop.stripeAccount && location && locationRefused(error)) {
      // The location we made is gone (deleted in the shop's Dashboard): the next try makes a new one.
      stripeFailure(deps, error, 'connection token');
      await forgetTerminalLocation(deps, shop.stripeAccount, location);
      throw new ApiError('server_error', "Stripe couldn't find the shop's Tap to Pay location. Try again, and a new one is set up.");
    }
    throw stripeFailure(deps, error, 'connection token');
  }
}

// POST /api/owner/payments { amountCents, description?, appointmentId?, receiptEmail?, sale? }

const paymentBody = z.object({
  amountCents: z
    .number({ error: `Enter an amount from $${MIN_AMOUNT_CENTS / 100} to $${MAX_AMOUNT_CENTS / 100}.` })
    .int({ error: 'The amount must be a whole number of cents.' })
    .min(MIN_AMOUNT_CENTS, { error: `The smallest card payment is $${(MIN_AMOUNT_CENTS / 100).toFixed(2)}.` })
    .max(MAX_AMOUNT_CENTS, { error: `The largest card payment is $${(MAX_AMOUNT_CENTS / 100).toLocaleString('en-US')}.` }),
  description: z
    .string({ error: 'The note must be text.' })
    .nullish()
    .transform((v) => {
      const t = v?.trim() ?? '';
      return t === '' ? null : t;
    })
    .refine((v) => v === null || charLength(v) <= 200, { error: 'Keep the note to 200 characters or fewer.' }),
  appointmentId: z.string({ error: 'appointmentId must be an appointment id.' }).nullish(),
  receiptEmail: email.optional(),
  /** A checkout's ticket (sales.ts): recorded as a card sale once this payment succeeds. */
  sale: cardSaleBody.optional(),
});

export async function createPayment(ctx: Context): Promise<Response> {
  // The owner key only: Tap to Pay is iPhone-only.
  await requireOwner(ctx, { keyOnly: true });
  const shop = await shopStripe(ctx.deps);
  const body = parse(paymentBody, await readJsonObject(ctx.request));
  const draft = body.sale ? await cardSaleDraft(ctx.deps.db, ctx.deps.catalog, body.sale, body) : null;
  const appointmentId = draft ? draft.appointmentId : (body.appointmentId ?? null);
  // A checkout's ticket has already found its appointment.
  if (appointmentId !== null && !draft) {
    const known =
      UUID_RE.test(appointmentId) &&
      ((await ctx.deps.db.query('SELECT 1 FROM appointments WHERE id = $1', [appointmentId])).rowCount ?? 0) > 0;
    if (!known) throw new ApiError('not_found', "We couldn't find that appointment.");
  }

  let intent: Stripe.PaymentIntent;
  try {
    intent = await shop.stripe.paymentIntents.create(
      {
        amount: body.amountCents,
        currency: 'usd',
        // Not payment_method_types: that's a 400 since API version 2026-09-30.endive.
        allowed_payment_method_types: ['card_present'],
        capture_method: 'automatic',
        ...(body.description ? { description: body.description } : {}),
        ...(body.receiptEmail ? { receipt_email: body.receiptEmail } : {}),
        metadata: { source: 'izzy-clipz-business', ...(appointmentId ? { appointment_id: appointmentId } : {}) },
      },
      requestOptions(shop),
    );
  } catch (error) {
    throw stripeFailure(ctx.deps, error, 'create payment');
  }
  if (!intent.client_secret) throw stripeFailure(ctx.deps, new Error('PaymentIntent has no client secret'), 'create payment');

  const now = ctx.deps.now();
  // With the account it was made on, so it's always looked up there, even after the shop connects
  // another; and with the checkout's ticket, recorded as a sale once the payment succeeds.
  await ctx.deps.db.query(
    `INSERT INTO payments (id, amount_cents, description, appointment_id, status, receipt_email, created_at, updated_at, stripe_account_id, sale_draft)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $7, $8, $9::jsonb)
     ON CONFLICT (id) DO NOTHING`,
    [
      intent.id,
      body.amountCents,
      body.description,
      appointmentId,
      intent.status,
      body.receiptEmail ?? null,
      now,
      shop.stripeAccount ?? null,
      draft ? JSON.stringify(draft) : null,
    ],
  );
  return json({ paymentIntentId: intent.id, clientSecret: intent.client_secret }, 201);
}

/**
 * Records Stripe's view of a PaymentIntent and, once it succeeded, records its
 * checkout's card sale (if it has a ticket) and marks its appointment paid
 * (paid amount = all succeeded payments for it). Idempotent.
 */
export async function syncPayment(
  db: Queryable,
  intent: Pick<Stripe.PaymentIntent, 'id' | 'status'>,
  now: Date,
  deps: Pick<Deps, 'uuid' | 'log'>,
): Promise<PaymentRow | null> {
  // succeeded and canceled are final in Stripe, so a late or replayed event can't undo them.
  await db.query(
    `UPDATE payments SET status = $2, updated_at = $3
      WHERE id = $1 AND status <> $2 AND status NOT IN ('succeeded', 'canceled')`,
    [intent.id, intent.status, now],
  );
  const { rows } = await db.query<PaymentRow>(`SELECT ${PAYMENT_COLUMNS} FROM payments WHERE id = $1`, [intent.id]);
  let row = rows[0];
  if (!row) return null;
  if (row.status === 'succeeded' && row.kind === 'in_person' && row.sale_id === null) {
    // In this same transaction, so the money is in the sales exactly when the payment is.
    if (await recordCardSale(db, deps, row.id, now)) {
      const { rows: recorded } = await db.query<PaymentRow>(`SELECT ${PAYMENT_COLUMNS} FROM payments WHERE id = $1`, [intent.id]);
      row = recorded[0] ?? row;
    }
  }
  // A fee charged to the card on file isn't a payment for the service: it never marks the appointment paid.
  if (row.status === 'succeeded' && row.appointment_id && row.kind === 'in_person') {
    await db.query(
      `UPDATE appointments a
          SET payment_status = 'paid',
              paid_cents = s.total,
              paid_at = COALESCE(a.paid_at, $3),
              payment_intent_id = $2,
              updated_at = $3
         FROM (SELECT COALESCE(sum(amount_cents), 0)::int AS total FROM payments
                WHERE appointment_id = $1 AND status = 'succeeded' AND kind = 'in_person') s
        WHERE a.id = $1`,
      [row.appointment_id, row.id, now],
    );
  }
  return row;
}

// POST /api/owner/payments/:id/complete — the app calls this after Tap to Pay finishes.

export async function completePayment(ctx: Context): Promise<Response> {
  await requireOwner(ctx);
  if (stripeSetup(ctx.deps.config) === 'off') throw stripeOff();
  const id = ctx.params.id ?? '';
  const notFound = () => new ApiError('not_found', "We couldn't find that payment.");
  if (!/^pi_[A-Za-z0-9_]+$/.test(id)) throw notFound();
  const known = await ctx.deps.db.query<{ kind: string; appointment_id: string | null; stripe_account_id: string | null }>(
    'SELECT kind, appointment_id, stripe_account_id FROM payments WHERE id = $1',
    [id],
  );
  const payment = known.rows[0];
  if (!payment) throw notFound();
  // Asked on the account the payment was made on: Stripe keeps it there, even after the shop connects another.
  const shop = await shopStripe(ctx.deps, { account: payment.stripe_account_id });

  let intent: Stripe.PaymentIntent;
  try {
    intent = await shop.stripe.paymentIntents.retrieve(id, undefined, requestOptions(shop));
  } catch (error) {
    throw stripeFailure(ctx.deps, error, 'retrieve payment');
  }
  if (intent.id !== id) throw notFound();
  const now = ctx.deps.now();
  const row = await ctx.deps.db.transaction(async (tx) => {
    // A fee (no-show or late cancellation) checked this way keeps its appointment's fee right too (and never marks it paid).
    if (isFeeKind(payment.kind)) {
      await syncNoShowFeeFromStripe(tx, intent, payment.appointment_id, ctx.deps, now, payment.kind, payment.stripe_account_id);
      const { rows } = await tx.query<PaymentRow>(`SELECT ${PAYMENT_COLUMNS} FROM payments WHERE id = $1`, [id]);
      return rows[0] ?? null;
    }
    return syncPayment(tx, intent, now, ctx.deps);
  });
  if (!row) throw notFound();
  // `status` is Stripe's: "succeeded" means the money is in. Anything else is not paid (yet).
  return json({ payment: paymentJSON(row) });
}

// GET /api/owner/payments?date=YYYY-MM-DD — payments started that shop-local day, newest first.

export async function listPayments(ctx: Context): Promise<Response> {
  await requireOwner(ctx);
  const { from, to } = dayRange(ctx);
  const zone = ctx.deps.catalog.timeZone;
  const { rows } = await ctx.deps.db.query<PaymentRow>(
    `SELECT ${PAYMENT_COLUMNS} FROM payments
      WHERE created_at >= $1 AND created_at < $2
      ORDER BY created_at DESC, id`,
    [dayBounds(from, zone).start, dayBounds(to, zone).end],
  );
  return json({ payments: rows.map(paymentJSON) });
}

// POST /api/stripe/webhook — signed by Stripe; the source of truth if the app never calls complete.
// Two endpoints may send here: the shop's own account's (STRIPE_WEBHOOK_SECRET), and in connect
// mode the platform's Connect endpoint, for events on connected accounts
// (STRIPE_CONNECT_WEBHOOK_SECRET). Those carry `account`.

const HANDLED_EVENTS = new Set([
  'payment_intent.succeeded',
  'payment_intent.payment_failed',
  'payment_intent.canceled',
  'payment_intent.processing',
  'payment_intent.requires_action',
]);

/** The event, if Stripe signed it with the secret of one of our two endpoints. */
function verifiedEvent(payload: string, signature: string, secrets: string[]): Stripe.Event | null {
  for (const secret of secrets) {
    try {
      return Stripe.webhooks.constructEvent(payload, signature, secret);
    } catch {
      // Signed for the other endpoint, or not by Stripe: try the next secret.
    }
  }
  return null;
}

interface PaymentRecord {
  kind: string;
  appointment_id: string | null;
  stripe_account_id: string | null;
}

/**
 * Whether an event from connected account `account` is about the shop: the account connected
 * now, the one the payment was made on, or (a fee this server never got to write down) the
 * one the appointment's card was saved on. A connected account of the platform that isn't the
 * shop's is ignored.
 */
async function shopsAccount(
  deps: Deps,
  tx: Queryable,
  account: string,
  known: PaymentRecord | undefined,
  metadata: Record<string, string> | null | undefined,
): Promise<boolean> {
  if (known) return known.stripe_account_id === account || (await currentConnection(deps, tx))?.accountId === account;
  if ((await currentConnection(deps, tx))?.accountId === account) return true;
  const appointmentId = metadata?.appointment_id ?? '';
  if (!isFeeKind(metadata?.kind) || !UUID_RE.test(appointmentId)) return false;
  const { rows } = await tx.query<{ stripe_account_id: string | null }>(
    'SELECT c.stripe_account_id FROM appointments a JOIN saved_cards c ON c.id = a.saved_card_id WHERE a.id = $1',
    [appointmentId],
  );
  return rows[0]?.stripe_account_id === account;
}

export async function stripeWebhook(ctx: Context): Promise<Response> {
  const { config } = ctx.deps;
  const secrets = [config.stripeWebhookSecret, config.stripeConnectWebhookSecret].filter((s): s is string => Boolean(s));
  if (secrets.length === 0) throw new ApiError('stripe_not_configured', 'Stripe webhooks are not set up on this server.');
  const signature = ctx.request.headers.get('stripe-signature');
  if (!signature) throw new ApiError('invalid_request', 'Missing Stripe-Signature header.');
  const payload = await readText(ctx.request, 512 * 1024);
  const event = verifiedEvent(payload, signature, secrets);
  if (!event) throw new ApiError('invalid_request', "The webhook signature doesn't match.");
  // Set on events from a connected account (the Connect endpoint).
  const account = typeof event.account === 'string' && event.account !== '' ? event.account : null;

  if (event.type === 'account.application.deauthorized') {
    // The shop took the platform's access to its account away (from its own Stripe Dashboard).
    if (account) await accountDeauthorized(ctx.deps, account);
    return json({ received: true });
  }

  if (event.type === 'account.updated') {
    const updated = event.data.object as { id?: unknown };
    const accountId = account ?? (typeof updated.id === 'string' ? updated.id : null);
    // Only the shop's connected account counts; its new status is read from Stripe and cached.
    if (accountId) await accountUpdated(ctx.deps, accountId);
    return json({ received: true });
  }

  if (HANDLED_EVENTS.has(event.type)) {
    const object = event.data.object as {
      object?: string;
      id?: string;
      status?: string;
      metadata?: Record<string, string> | null;
      last_payment_error?: { code?: string | null; decline_code?: string | null } | null;
      created?: number;
    };
    if (object.object === 'payment_intent' && typeof object.id === 'string' && typeof object.status === 'string') {
      const intent = { id: object.id, status: object.status as Stripe.PaymentIntent.Status };
      const now = ctx.deps.now();
      await ctx.deps.db.transaction(async (tx) => {
        const { rows } = await tx.query<PaymentRecord>('SELECT kind, appointment_id, stripe_account_id FROM payments WHERE id = $1', [
          intent.id,
        ]);
        const known = rows[0];
        if (account !== null && !(await shopsAccount(ctx.deps, tx, account, known, object.metadata))) return;
        // Fees charged to a card on file follow the appointment's fee; one this server never got to record is found by its metadata.
        if (isFeeKind(known?.kind) || (!known && isFeeKind(object.metadata?.kind))) {
          await syncNoShowFeeFromStripe(
            tx,
            {
              ...intent,
              metadata: object.metadata ?? null,
              last_payment_error: object.last_payment_error ?? null,
              created: typeof object.created === 'number' ? object.created : null,
            },
            known?.appointment_id ?? null,
            ctx.deps,
            now,
            known?.kind ?? null,
            known ? known.stripe_account_id : account,
          );
          return;
        }
        await syncPayment(tx, intent, now, ctx.deps);
      });
    }
  }
  return json({ received: true });
}
