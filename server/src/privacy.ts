import { parseArgs } from 'node:util';
import type { SavedCardRow } from './cards.js';
import type { Queryable } from './db.js';
import type { Deps } from './deps.js';
import { feeDeadline } from './feecase.js';
import { anonymizeAppointments, anonymizePayments, anonymizeSales, detailsStillNeeded, removeCard } from './retention.js';
import { loadSales, saleJSON } from './sales.js';
import { appointmentJSON, PAYMENT_COLUMNS, paymentJSON, type AppointmentRow, type PaymentRow } from './serialize.js';
import { formatInstant } from './time.js';
import { email as emailField, normalizeUSPhone, personName, UUID_RE } from './validation.js';

// Answering a client's privacy request (docs/legal/privacy.md, "Your choices and rights";
// research.md §3 and §18 item 9; data-inventory.md G3), once the shop has checked it's them by
// calling or texting the number on file. Run by the owner next to `npm run migrate`
// (scripts/privacy.ts reads DATABASE_URL, and STRIPE_SECRET_KEY to delete cards):
//
//   npm run privacy:find -- --phone "(442) 555-0170"    (or --email or --name; --out file.json to save it)
//   npm run privacy:correct -- --appointment <id> --name "…" --phone "…" --email "…"
//   npm run privacy:forget -- --phone "(442) 555-0170"  (or --email or --name; --dry-run to only show what it would do)
//
// A person is found by the mobile number (any way it's written) or the email on their
// appointments, or, for someone the shop knows only by name (a walk-in booked at the shop without
// a number, or a checkout with a typed name), by that name, written the same way (any capitals):
// their appointments, and their walk-in checkouts with no appointment. Names aren't unique, so a
// search by name says so, and the owner checks each record with the client before sending or
// deleting anything. What's linked to the appointments comes with them: their checkouts (sales),
// card payments and fees, and the cards saved for them.

export class PrivacyError extends Error {}

export interface Person {
  phone?: string | undefined;
  email?: string | undefined;
  name?: string | undefined;
}

type Who = { phone: string } | { email: string } | { name: string };

/** What a search by name says with what it found: names aren't unique. */
export const SAME_NAME_NOTE =
  "Found by name. Names aren't unique: check every appointment and sale here with the client before you send it or delete anything.";

/** The phone number (E.164), email (lowercase) or name (spaces tidied) to look for; exactly one of them. */
function who(person: Person): Who {
  const phone = person.phone?.trim();
  const email = person.email?.trim();
  const name = person.name?.trim().replace(/\s+/g, ' ');
  if ([phone, email, name].filter(Boolean).length > 1) {
    throw new PrivacyError('Look for one person at a time: give --phone, --email or --name, not more than one.');
  }
  if (name) return { name };
  if (phone) {
    const normalized = normalizeUSPhone(phone);
    if (!normalized) throw new PrivacyError('Enter a US mobile number, like (442) 341-3053.');
    return { phone: normalized };
  }
  if (email) {
    const parsed = emailField.safeParse(email);
    if (!parsed.success || !parsed.data) throw new PrivacyError('Enter a valid email address.');
    return { email: parsed.data.toLowerCase() };
  }
  throw new PrivacyError('Give the --phone or the --email the client booked with, or the --name the shop knows them by.');
}

async function appointmentsOf(db: Queryable, person: Person): Promise<{ who: Who; rows: AppointmentRow[] }> {
  const key = who(person);
  const { rows } =
    'phone' in key
      ? await db.query<AppointmentRow>('SELECT * FROM appointments WHERE customer_phone = $1 ORDER BY start_at, id', [key.phone])
      : 'email' in key
        ? await db.query<AppointmentRow>('SELECT * FROM appointments WHERE lower(customer_email) = $1 ORDER BY start_at, id', [key.email])
        : await db.query<AppointmentRow>(
            `SELECT * FROM appointments WHERE anonymized_at IS NULL AND lower(regexp_replace(btrim(customer_name), '\\s+', ' ', 'g')) = lower($1)
              ORDER BY start_at, id`,
            [key.name],
          );
  return { who: key, rows };
}

/** For a search by name, the walk-in checkouts with that name and no appointment (their ids), whose details go with the person's. */
async function walkInSalesOf(db: Queryable, key: Who): Promise<string[]> {
  if (!('name' in key)) return [];
  const { rows } = await db.query<{ id: string }>(
    `SELECT id FROM sales
      WHERE appointment_id IS NULL AND anonymized_at IS NULL AND lower(regexp_replace(btrim(customer_name), '\\s+', ' ', 'g')) = lower($1)
      ORDER BY sold_at, id`,
    [key.name],
  );
  return rows.map((row) => row.id);
}

function cardJSON(card: SavedCardRow) {
  return {
    id: card.id,
    brand: card.brand,
    last4: card.last4,
    expMonth: card.exp_month,
    expYear: card.exp_year,
    savedAt: formatInstant(card.created_at),
    removedAt: card.removed_at ? formatInstant(card.removed_at) : null,
    deleteRequestedAt: card.delete_requested_at ? formatInstant(card.delete_requested_at) : null,
  };
}

/**
 * Everything the shop keeps about the person, as JSON: their appointments (with the cancellation
 * and no-show terms they agreed to, word for word, and when), checkouts, card payments and fees,
 * and saved cards (only the type, last 4 and expiry: the shop never has the card number).
 */
export async function findPersonData(deps: Pick<Deps, 'db' | 'now'>, person: Person) {
  const { who: key, rows } = await appointmentsOf(deps.db, person);
  const ids = rows.map((r) => r.id);
  const walkIns = await walkInSalesOf(deps.db, key);
  const sales =
    ids.length > 0 || walkIns.length > 0
      ? await loadSales(deps.db, '(s.appointment_id = ANY($1::uuid[]) OR s.id = ANY($2::uuid[]))', [ids, walkIns], 's.sold_at, s.id')
      : [];
  // Card payments of the appointments, and of the walk-in checkouts paid by card.
  const { rows: payments } =
    ids.length > 0 || walkIns.length > 0
      ? await deps.db.query<PaymentRow>(
          `SELECT ${PAYMENT_COLUMNS} FROM payments
            WHERE appointment_id = ANY($1::uuid[]) OR id IN (SELECT payment_intent_id FROM sales WHERE id = ANY($2::uuid[]) AND payment_intent_id IS NOT NULL)
            ORDER BY created_at, id`,
          [ids, walkIns],
        )
      : { rows: [] as PaymentRow[] };
  const cardIds = [...new Set(rows.map((r) => r.saved_card_id).filter((id): id is string => id !== null))];
  const { rows: cards } =
    cardIds.length > 0
      ? await deps.db.query<SavedCardRow>('SELECT * FROM saved_cards WHERE id = ANY($1::uuid[]) ORDER BY created_at', [cardIds])
      : { rows: [] as SavedCardRow[] };
  return {
    person: key,
    ...('name' in key ? { note: SAME_NAME_NOTE } : {}),
    exportedAt: formatInstant(deps.now()),
    appointments: rows.map((row) => ({
      ...appointmentJSON(row),
      bookedBy: row.booked_by,
      // The exact terms the client agreed to when booking with a card on file, and when.
      noShowPolicy: row.no_show_policy,
      noShowConsentAt: row.no_show_consent_at ? formatInstant(row.no_show_consent_at) : null,
    })),
    sales: sales.map(saleJSON),
    payments: payments.map(paymentJSON),
    savedCards: cards.map(cardJSON),
  };
}

export interface Correction {
  name?: string | undefined;
  phone?: string | undefined;
  email?: string | undefined;
}

/**
 * Fixes a typo in an appointment's name, number or email (an empty number or email removes it),
 * and the same name where its checkout copied it: on its sale, and on a card checkout's ticket
 * (kept with the payment; the sale takes its name from it once the card goes through). A name
 * typed differently at the checkout stays. Not for an appointment whose details were already
 * removed.
 */
export async function correctAppointment(deps: Pick<Deps, 'db' | 'now'>, id: string, changes: Correction) {
  if (!UUID_RE.test(id)) throw new PrivacyError("That isn't an appointment id (it looks like 1b4e28ba-2fa1-11d2-883f-0016d3cca427).");
  if (changes.name === undefined && changes.phone === undefined && changes.email === undefined) {
    throw new PrivacyError('Give what to correct: --name, --phone or --email.');
  }
  let name: string | undefined;
  if (changes.name !== undefined) {
    const parsed = personName.safeParse(changes.name);
    if (!parsed.success) throw new PrivacyError(parsed.error.issues[0]?.message ?? 'Enter the name.');
    name = parsed.data;
  }
  let phone: string | null | undefined;
  if (changes.phone !== undefined) {
    phone = changes.phone.trim() === '' ? null : normalizeUSPhone(changes.phone);
    if (phone === null && changes.phone.trim() !== '') throw new PrivacyError('Enter a US mobile number, like (442) 341-3053, or "" to remove it.');
  }
  let email: string | null | undefined;
  if (changes.email !== undefined) {
    const parsed = emailField.safeParse(changes.email);
    if (!parsed.success) throw new PrivacyError('Enter a valid email address, or "" to remove it.');
    email = parsed.data;
  }
  const now = deps.now();
  return deps.db.transaction(async (tx) => {
    const { rows } = await tx.query<AppointmentRow>('SELECT * FROM appointments WHERE id = $1 FOR UPDATE', [id]);
    const row = rows[0];
    if (!row) throw new PrivacyError("We couldn't find that appointment.");
    if (row.anonymized_at) throw new PrivacyError("This appointment's details were already removed, so there's nothing to correct.");
    const { rows: updated } = await tx.query<AppointmentRow>(
      `UPDATE appointments
          SET customer_name = CASE WHEN $2::boolean THEN $3 ELSE customer_name END,
              customer_phone = CASE WHEN $4::boolean THEN $5 ELSE customer_phone END,
              customer_email = CASE WHEN $6::boolean THEN $7 ELSE customer_email END,
              updated_at = $8
        WHERE id = $1
        RETURNING *`,
      [id, name !== undefined, name ?? null, phone !== undefined, phone ?? null, email !== undefined, email ?? null, now],
    );
    const sales =
      name === undefined
        ? 0
        : ((
            await tx.query('UPDATE sales SET customer_name = $2, updated_at = $3 WHERE appointment_id = $1 AND customer_name = $4 AND anonymized_at IS NULL', [
              id,
              name,
              now,
              row.customer_name,
            ])
          ).rowCount ?? 0);
    // A ticket names its appointment even when its sale was recorded without it (sales.ts).
    const tickets =
      name === undefined
        ? 0
        : ((
            await tx.query(
              `UPDATE payments SET sale_draft = jsonb_set(sale_draft, '{customerName}', to_jsonb($2::text)), updated_at = $3
                WHERE sale_draft->>'appointmentId' = $1::text AND sale_draft->>'customerName' = $4 AND anonymized_at IS NULL`,
              [id, name, now, row.customer_name],
            )
          ).rowCount ?? 0);
    return { appointment: appointmentJSON(updated[0] ?? row), salesCorrected: sales, cardTicketsCorrected: tickets };
  });
}

/**
 * Deletes the person's details now, as the daily job does after 12 months: from their appointments,
 * except one still needed (upcoming, or one whose fee is pending or can still be charged within the
 * 7 days), and from those appointments' checkouts and card payments. Their saved cards are deleted
 * at Stripe, or as soon as no booking needs them (like DELETE /api/cards). `dryRun` only says what
 * would happen. Run it again after `runAgainAfter` for the appointments it had to keep.
 */
export async function forgetPerson(deps: Pick<Deps, 'config' | 'db' | 'stripe' | 'log' | 'now'>, person: Person, options: { dryRun?: boolean } = {}) {
  const now = deps.now();
  const { who: key, rows } = await appointmentsOf(deps.db, person);
  const kept = rows.flatMap((row) => {
    const reason = detailsStillNeeded(row, now);
    return reason ? [{ id: row.id, start: formatInstant(row.start_at), reason }] : [];
  });
  const keptIds = new Set(kept.map((k) => k.id));
  const removable = rows.filter((row) => !keptIds.has(row.id)).map((row) => row.id);
  // Found by name: their walk-in checkouts with no appointment too.
  const walkIns = await walkInSalesOf(deps.db, key);
  const { rows: sales } =
    removable.length > 0 || walkIns.length > 0
      ? await deps.db.query<{ id: string }>('SELECT id FROM sales WHERE appointment_id = ANY($1::uuid[]) OR id = ANY($2::uuid[])', [removable, walkIns])
      : { rows: [] as { id: string }[] };
  const { rows: payments } =
    removable.length > 0 || walkIns.length > 0
      ? await deps.db.query<{ id: string }>(
          `SELECT id FROM payments
            WHERE appointment_id = ANY($1::uuid[]) OR id IN (SELECT payment_intent_id FROM sales WHERE id = ANY($2::uuid[]) AND payment_intent_id IS NOT NULL)`,
          [removable, walkIns],
        )
      : { rows: [] as { id: string }[] };
  const cardIds = [...new Set(rows.map((r) => r.saved_card_id).filter((id): id is string => id !== null))];
  const latest = rows.filter((row) => keptIds.has(row.id)).map((row) => feeDeadline(row.start_at).getTime());
  const result = {
    person: key,
    ...('name' in key ? { note: SAME_NAME_NOTE } : {}),
    dryRun: options.dryRun === true,
    appointments: { removed: removable.length, kept },
    sales: sales.length,
    payments: payments.length,
    savedCards: { deleted: 0, scheduled: 0, found: cardIds.length },
    runAgainAfter: latest.length > 0 ? formatInstant(new Date(Math.max(...latest))) : null,
  };
  if (options.dryRun) return result;
  result.appointments.removed = await anonymizeAppointments(deps.db, removable, now);
  result.sales = await anonymizeSales(deps.db, sales.map((s) => s.id), now);
  result.payments = await anonymizePayments(deps.db, payments.map((p) => p.id), now);
  const { rows: cards } =
    cardIds.length > 0
      ? await deps.db.query<SavedCardRow>('SELECT * FROM saved_cards WHERE id = ANY($1::uuid[]) ORDER BY created_at', [cardIds])
      : { rows: [] as SavedCardRow[] };
  for (const card of cards) {
    if ((await removeCard(deps, card, now)) === 'deleted') result.savedCards.deleted += 1;
    else result.savedCards.scheduled += 1;
  }
  return result;
}

// The command line (scripts/privacy.ts): `privacy <find|correct|forget> [options]`.

export const PRIVACY_USAGE = `Answer a client's privacy request, after checking it's them (call or text the number on file):

  npm run privacy:find -- --phone "(442) 555-0170" [--out request.json]
  npm run privacy:find -- --email client@example.com
  npm run privacy:find -- --name "Andre Sample"
  npm run privacy:correct -- --appointment <id> [--name "Name"] [--phone "(442) 555-0170"] [--email "a@b.com"]
  npm run privacy:forget -- --phone "(442) 555-0170" [--dry-run]

find prints everything kept about that person as JSON (save it with --out and send it to them).
--name is for someone the shop knows only by name (a walk-in booked without a number, a checkout with a typed name): names aren't unique, so run find first and check every record with the client before forget --name.
correct fixes an appointment's name, number or email ("" removes the number or email), and the same name where its checkout copied it.
forget removes their name, number, email and notes now, except from appointments still needed (it says which, and when to run it again), and deletes their saved cards at Stripe.`;

/** Runs one command; what to print, and the exit code. */
export async function privacyCommand(
  argv: string[],
  deps: Pick<Deps, 'config' | 'db' | 'stripe' | 'log' | 'now'>,
): Promise<{ output: string; exitCode: number; file?: { path: string; text: string } }> {
  let parsed;
  try {
    parsed = parseArgs({
      args: argv,
      allowPositionals: true,
      options: {
        phone: { type: 'string' },
        email: { type: 'string' },
        appointment: { type: 'string' },
        name: { type: 'string' },
        out: { type: 'string' },
        'dry-run': { type: 'boolean' },
        help: { type: 'boolean' },
      },
    });
  } catch (error) {
    return { output: `${error instanceof Error ? error.message : String(error)}\n\n${PRIVACY_USAGE}`, exitCode: 2 };
  }
  const { values, positionals } = parsed;
  const command = positionals[0];
  if (values.help || !command) return { output: PRIVACY_USAGE, exitCode: command || values.help ? 0 : 2 };
  try {
    switch (command) {
      case 'find': {
        const text = `${JSON.stringify(await findPersonData(deps, { phone: values.phone, email: values.email, name: values.name }), null, 2)}\n`;
        if (values.out) return { output: `Saved to ${values.out}.`, exitCode: 0, file: { path: values.out, text } };
        return { output: text, exitCode: 0 };
      }
      case 'correct': {
        if (!values.appointment) throw new PrivacyError('Give the --appointment id (privacy:find shows it).');
        const corrected = await correctAppointment(deps, values.appointment, { name: values.name, phone: values.phone, email: values.email });
        return { output: `${JSON.stringify(corrected, null, 2)}\n`, exitCode: 0 };
      }
      case 'forget': {
        const forgotten = await forgetPerson(deps, { phone: values.phone, email: values.email, name: values.name }, { dryRun: values['dry-run'] === true });
        return { output: `${JSON.stringify(forgotten, null, 2)}\n`, exitCode: 0 };
      }
      default:
        return { output: `Unknown command "${command}".\n\n${PRIVACY_USAGE}`, exitCode: 2 };
    }
  } catch (error) {
    if (error instanceof PrivacyError) return { output: error.message, exitCode: 1 };
    throw error;
  }
}
