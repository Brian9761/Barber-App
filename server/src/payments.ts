import Stripe from 'stripe';
import { z } from 'zod';
import { dayRange } from './appointments.js';
import { requireOwner } from './auth.js';
import type { Config } from './config.js';
import type { Queryable } from './db.js';
import type { Deps, StripeClient } from './deps.js';
import { ApiError, json, readJsonObject, readText } from './http.js';
import type { Context } from './router.js';
import { paymentJSON, type PaymentRow } from './serialize.js';
import { dayBounds } from './time.js';
import { charLength, email, parse, UUID_RE } from './validation.js';

// In-person card payments with Stripe Terminal (Tap to Pay on iPhone). The
// server creates every PaymentIntent, so the app can't change the amount, and
// checks with Stripe before marking anything paid.

export const MIN_AMOUNT_CENTS = 50;
export const MAX_AMOUNT_CENTS = 100_000;

export type StripeMode = 'test' | 'live' | null;

export function stripeMode(config: Config): StripeMode {
  const key = config.stripeSecretKey;
  if (!key) return null;
  if (/^(sk|rk)_test_/.test(key)) return 'test';
  if (/^(sk|rk)_live_/.test(key)) return 'live';
  return null;
}

function stripeClient(deps: Deps): StripeClient {
  const key = deps.config.stripeSecretKey;
  if (!key) {
    throw new ApiError('stripe_not_configured', "Card payments aren't set up yet. Add the shop's Stripe key on the server.");
  }
  return deps.stripe(key);
}

/** Stripe's own errors: a missing object becomes a 404, anything else a 500 with a plain message. */
function stripeFailure(deps: Deps, error: unknown, what: string): ApiError {
  if (error instanceof ApiError) return error;
  const e = error as { type?: string; code?: string; statusCode?: number; message?: string };
  if (e?.code === 'resource_missing' || e?.statusCode === 404) {
    return new ApiError('not_found', "Stripe doesn't know that payment.");
  }
  deps.log.error(`Stripe ${what} failed`, { type: e?.type, code: e?.code, status: e?.statusCode, message: e?.message });
  return new ApiError('server_error', "We couldn't reach Stripe. Please try again.");
}

// GET /api/owner/me

export async function ownerMe(ctx: Context): Promise<Response> {
  requireOwner(ctx.request, ctx.deps.config);
  const configured = Boolean(ctx.deps.config.stripeSecretKey);
  // The app needs the Terminal location to connect Tap to Pay (TapToPayConnectionConfiguration).
  const locationId = configured ? (ctx.deps.config.stripeTerminalLocationId ?? null) : null;
  return json({ ok: true, stripe: { configured, mode: configured ? stripeMode(ctx.deps.config) : null, locationId } });
}

// POST /api/owner/terminal/connection-token

export async function connectionToken(ctx: Context): Promise<Response> {
  requireOwner(ctx.request, ctx.deps.config);
  const stripe = stripeClient(ctx.deps);
  const location = ctx.deps.config.stripeTerminalLocationId;
  try {
    const token = await stripe.terminal.connectionTokens.create(location ? { location } : {});
    return json({ secret: token.secret });
  } catch (error) {
    throw stripeFailure(ctx.deps, error, 'connection token');
  }
}

// POST /api/owner/payments { amountCents, description?, appointmentId?, receiptEmail? }

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
});

export async function createPayment(ctx: Context): Promise<Response> {
  requireOwner(ctx.request, ctx.deps.config);
  const stripe = stripeClient(ctx.deps);
  const body = parse(paymentBody, await readJsonObject(ctx.request));
  const appointmentId = body.appointmentId ?? null;
  if (appointmentId !== null) {
    const known =
      UUID_RE.test(appointmentId) &&
      ((await ctx.deps.db.query('SELECT 1 FROM appointments WHERE id = $1', [appointmentId])).rowCount ?? 0) > 0;
    if (!known) throw new ApiError('not_found', "We couldn't find that appointment.");
  }

  let intent: Stripe.PaymentIntent;
  try {
    intent = await stripe.paymentIntents.create({
      amount: body.amountCents,
      currency: 'usd',
      // Not payment_method_types: that's a 400 since API version 2026-09-30.endive.
      allowed_payment_method_types: ['card_present'],
      capture_method: 'automatic',
      ...(body.description ? { description: body.description } : {}),
      ...(body.receiptEmail ? { receipt_email: body.receiptEmail } : {}),
      metadata: { source: 'izzy-clipz-business', ...(appointmentId ? { appointment_id: appointmentId } : {}) },
    });
  } catch (error) {
    throw stripeFailure(ctx.deps, error, 'create payment');
  }
  if (!intent.client_secret) throw stripeFailure(ctx.deps, new Error('PaymentIntent has no client secret'), 'create payment');

  const now = ctx.deps.now();
  await ctx.deps.db.query(
    `INSERT INTO payments (id, amount_cents, description, appointment_id, status, receipt_email, created_at, updated_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $7)
     ON CONFLICT (id) DO NOTHING`,
    [intent.id, body.amountCents, body.description, appointmentId, intent.status, body.receiptEmail ?? null, now],
  );
  return json({ paymentIntentId: intent.id, clientSecret: intent.client_secret }, 201);
}

/**
 * Records Stripe's view of a PaymentIntent and, once it succeeded, marks its
 * appointment paid (paid amount = all succeeded payments for it). Idempotent.
 */
export async function syncPayment(
  db: Queryable,
  intent: Pick<Stripe.PaymentIntent, 'id' | 'status'>,
  now: Date,
): Promise<PaymentRow | null> {
  // succeeded and canceled are final in Stripe, so a late or replayed event can't undo them.
  await db.query(
    `UPDATE payments SET status = $2, updated_at = $3
      WHERE id = $1 AND status <> $2 AND status NOT IN ('succeeded', 'canceled')`,
    [intent.id, intent.status, now],
  );
  const { rows } = await db.query<PaymentRow>(
    `SELECT id, amount_cents, description, appointment_id, status, receipt_email, created_at
       FROM payments WHERE id = $1`,
    [intent.id],
  );
  const row = rows[0];
  if (!row) return null;
  if (row.status === 'succeeded' && row.appointment_id) {
    await db.query(
      `UPDATE appointments a
          SET payment_status = 'paid',
              paid_cents = s.total,
              paid_at = COALESCE(a.paid_at, $3),
              payment_intent_id = $2,
              updated_at = $3
         FROM (SELECT COALESCE(sum(amount_cents), 0)::int AS total FROM payments
                WHERE appointment_id = $1 AND status = 'succeeded') s
        WHERE a.id = $1`,
      [row.appointment_id, row.id, now],
    );
  }
  return row;
}

// POST /api/owner/payments/:id/complete — the app calls this after Tap to Pay finishes.

export async function completePayment(ctx: Context): Promise<Response> {
  requireOwner(ctx.request, ctx.deps.config);
  const stripe = stripeClient(ctx.deps);
  const id = ctx.params.id ?? '';
  const notFound = () => new ApiError('not_found', "We couldn't find that payment.");
  if (!/^pi_[A-Za-z0-9_]+$/.test(id)) throw notFound();
  const known = await ctx.deps.db.query('SELECT 1 FROM payments WHERE id = $1', [id]);
  if (!known.rowCount) throw notFound();

  let intent: Stripe.PaymentIntent;
  try {
    intent = await stripe.paymentIntents.retrieve(id);
  } catch (error) {
    throw stripeFailure(ctx.deps, error, 'retrieve payment');
  }
  if (intent.id !== id) throw notFound();
  const row = await ctx.deps.db.transaction((tx) => syncPayment(tx, intent, ctx.deps.now()));
  if (!row) throw notFound();
  // `status` is Stripe's: "succeeded" means the money is in. Anything else is not paid (yet).
  return json({ payment: paymentJSON(row) });
}

// GET /api/owner/payments?date=YYYY-MM-DD — payments started that shop-local day, newest first.

export async function listPayments(ctx: Context): Promise<Response> {
  requireOwner(ctx.request, ctx.deps.config);
  const { from, to } = dayRange(ctx);
  const zone = ctx.deps.catalog.timeZone;
  const { rows } = await ctx.deps.db.query<PaymentRow>(
    `SELECT id, amount_cents, description, appointment_id, status, receipt_email, created_at FROM payments
      WHERE created_at >= $1 AND created_at < $2
      ORDER BY created_at DESC, id`,
    [dayBounds(from, zone).start, dayBounds(to, zone).end],
  );
  return json({ payments: rows.map(paymentJSON) });
}

// POST /api/stripe/webhook — signed by Stripe; the source of truth if the app never calls complete.

const HANDLED_EVENTS = new Set([
  'payment_intent.succeeded',
  'payment_intent.payment_failed',
  'payment_intent.canceled',
  'payment_intent.processing',
  'payment_intent.requires_action',
]);

export async function stripeWebhook(ctx: Context): Promise<Response> {
  const secret = ctx.deps.config.stripeWebhookSecret;
  if (!secret) throw new ApiError('stripe_not_configured', 'Stripe webhooks are not set up on this server.');
  const signature = ctx.request.headers.get('stripe-signature');
  if (!signature) throw new ApiError('invalid_request', 'Missing Stripe-Signature header.');
  const payload = await readText(ctx.request, 512 * 1024);
  let event: Stripe.Event;
  try {
    event = Stripe.webhooks.constructEvent(payload, signature, secret);
  } catch {
    throw new ApiError('invalid_request', "The webhook signature doesn't match.");
  }
  if (HANDLED_EVENTS.has(event.type)) {
    const object = event.data.object as { object?: string; id?: string; status?: string };
    if (object.object === 'payment_intent' && typeof object.id === 'string' && typeof object.status === 'string') {
      const intent = { id: object.id, status: object.status as Stripe.PaymentIntent.Status };
      await ctx.deps.db.transaction((tx) => syncPayment(tx, intent, ctx.deps.now()));
    }
  }
  return json({ received: true });
}
