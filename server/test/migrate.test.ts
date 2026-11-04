import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { Catalog, loadCatalog } from '../src/catalog.js';
import { migrate, migrationFiles, seedBarbers } from '../src/migrate.js';
import { startTestDatabase, type TestDatabase } from './helpers/db.js';

let db: TestDatabase;
beforeAll(async () => {
  db = await startTestDatabase();
}, 60_000);
afterAll(async () => {
  await db?.close();
});

describe('npm run migrate', () => {
  it('applied every migration once, recorded with its checksum', async () => {
    const { rows } = await db.pool.query('SELECT version, checksum FROM schema_migrations ORDER BY version');
    expect(rows).toEqual(migrationFiles().map((f) => ({ version: f.name, checksum: f.checksum })));
    expect(rows.map((r) => r.version)).toEqual([
      '001_init.sql',
      '002_manage_token_unique.sql',
      '003_owner_idempotency_key.sql',
      '004_no_show_protection.sql',
      '006_sales.sql',
    ]);
  });

  it('is idempotent: running again applies nothing', async () => {
    const client = await db.pool.connect();
    try {
      const again = await migrate(client);
      expect(again.applied).toEqual([]);
      expect(again.skipped).toEqual(migrationFiles().map((f) => f.name));
    } finally {
      client.release();
    }
  });

  it('applies new files in order and refuses an edited one', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'izzy-migrations-'));
    for (const f of migrationFiles()) writeFileSync(join(dir, f.name), f.sql);
    writeFileSync(join(dir, '900_extra.sql'), 'CREATE TABLE migration_probe (id int);');
    writeFileSync(join(dir, 'notes.txt'), 'ignored');
    const url = pathToFileURL(`${dir}/`);
    const client = await db.pool.connect();
    try {
      expect((await migrate(client, url)).applied).toEqual(['900_extra.sql']);
      expect((await migrate(client, url)).applied).toEqual([]);
      writeFileSync(join(dir, '900_extra.sql'), 'CREATE TABLE migration_probe (id bigint);');
      await expect(migrate(client, url)).rejects.toThrow('900_extra.sql changed after it was applied');
      // The failed run left nothing half-done.
      expect((await client.query(`SELECT count(*)::int AS n FROM schema_migrations`)).rows[0].n).toBe(migrationFiles().length + 1);
    } finally {
      client.release();
    }
  });

  it('seeds the barbers from catalog.json, idempotently, and retires removed ones', async () => {
    const catalog = loadCatalog();
    const client = await db.pool.connect();
    // The test pool may have a single connection, so everything goes through `client`.
    const read = async () => (await client.query('SELECT id, name, sort, active FROM barbers ORDER BY sort, id')).rows;
    try {
      expect(await read()).toEqual(catalog.barbers.map((b, i) => ({ id: b.id, name: b.name, sort: i, active: true })));
      await seedBarbers(client, catalog);
      expect(await read()).toHaveLength(catalog.barbers.length);
      const raw = JSON.parse(readFileSync(new URL('../data/catalog.json', import.meta.url), 'utf8'));
      const smaller = new Catalog({
        ...raw,
        barbers: raw.barbers.filter((b: { id: string }) => b.id !== 'julian-ramos'),
        offerings: raw.offerings.filter((o: { barberId: string }) => o.barberId !== 'julian-ramos'),
        firstAvailable: raw.firstAvailable
          .map((fa: { serviceId: string; offeringIds: string[] }) => ({ ...fa, offeringIds: fa.offeringIds.filter((id) => !id.startsWith('julian-ramos/')) }))
          .filter((fa: { offeringIds: string[] }) => fa.offeringIds.length > 0),
      });
      expect(await seedBarbers(client, smaller)).toEqual({ active: 4, inactive: 1 });
      expect((await read()).find((b) => b.id === 'julian-ramos')).toMatchObject({ active: false });
      await seedBarbers(client, catalog);
      expect((await read()).every((b) => b.active)).toBe(true);
    } finally {
      client.release();
    }
  });

  it('003 adds the owner app’s idempotency key: hashes only, unique when set', async () => {
    const column = await db.pool.query(
      `SELECT data_type, is_nullable FROM information_schema.columns WHERE table_name = 'appointments' AND column_name = 'idempotency_key_hash'`,
    );
    expect(column.rows).toEqual([{ data_type: 'text', is_nullable: 'YES' }]);
    const index = await db.pool.query(`SELECT indexdef FROM pg_indexes WHERE indexname = 'appointments_idempotency_key_hash_key'`);
    expect(index.rows[0].indexdef).toBe(
      'CREATE UNIQUE INDEX appointments_idempotency_key_hash_key ON public.appointments USING btree (idempotency_key_hash) WHERE (idempotency_key_hash IS NOT NULL)',
    );
  });

  it('004 adds saved cards (hashes and Stripe ids only), settings, the fee columns and the payment kind', async () => {
    const columns = async (table: string) =>
      (await db.pool.query(`SELECT column_name FROM information_schema.columns WHERE table_name = $1 ORDER BY column_name`, [table])).rows.map(
        (r) => r.column_name,
      );
    expect(await columns('saved_cards')).toEqual([
      'brand',
      'checkout_session_id',
      'created_at',
      'exp_month',
      'exp_year',
      'id',
      'last4',
      'livemode',
      'stripe_customer_id',
      'stripe_payment_method_id',
      'token_hash',
    ]);
    expect(await columns('settings')).toEqual(['key', 'updated_at', 'value']);
    const appointmentColumns = await columns('appointments');
    for (const c of [
      'saved_card_id',
      'card_brand',
      'card_last4',
      'no_show_fee_cents',
      'no_show_policy',
      'no_show_consent_at',
      'no_show_fee_status',
      'no_show_fee_attempt',
      'no_show_fee_payment_intent_id',
      'no_show_fee_message',
      'no_show_fee_charged_at',
      'no_show_fee_attempt_at',
      'no_show_fee_reason',
      'late_cancel_window_minutes',
      'customer_cancelled_at',
    ]) {
      expect(appointmentColumns, c).toContain(c);
    }
    const kind = await db.pool.query(
      `SELECT column_default, is_nullable FROM information_schema.columns WHERE table_name = 'payments' AND column_name = 'kind'`,
    );
    expect(kind.rows).toEqual([{ column_default: "'in_person'::text", is_nullable: 'NO' }]);
    // The payment kinds: in person, and the two fees charged to a card on file.
    const kindCheck = await db.pool.query(
      `SELECT pg_get_constraintdef(oid) AS def FROM pg_constraint WHERE conrelid = 'payments'::regclass AND contype = 'c' AND pg_get_constraintdef(oid) LIKE '%kind%'`,
    );
    expect(kindCheck.rows).toHaveLength(1);
    for (const k of ['in_person', 'no_show_fee', 'late_cancel_fee']) expect(kindCheck.rows[0].def).toContain(`'${k}'`);
    const unique = await db.pool.query(
      `SELECT conname FROM pg_constraint WHERE conrelid = 'saved_cards'::regclass AND contype = 'u' ORDER BY conname`,
    );
    expect(unique.rows.map((r) => r.conname)).toEqual(['saved_cards_checkout_session_id_key', 'saved_cards_token_hash_key']);
    // A bad token hash or a full card number can't get in.
    await expect(
      db.pool.query(
        `INSERT INTO saved_cards VALUES (gen_random_uuid(), 'not-a-hash', 'cs_test_x', 'cus_x', 'pm_x', 'visa', '4242424242424242', 1, 2030, false, now())`,
      ),
    ).rejects.toThrow();
  });

  it('006 adds sales and their items, the card ticket on payments and the live sale on appointments, with their guarantees', async () => {
    const columns = async (table: string) =>
      (await db.pool.query(`SELECT column_name FROM information_schema.columns WHERE table_name = $1 ORDER BY column_name`, [table])).rows.map(
        (r) => r.column_name,
      );
    expect(await columns('sales')).toEqual([
      'appointment_id',
      'barber_id',
      'created_at',
      'customer_name',
      'id',
      'idempotency_key_hash',
      'method',
      'payment_intent_id',
      'sold_at',
      'total_cents',
      'updated_at',
      'void_reason',
      'voided_at',
    ]);
    expect(await columns('sale_items')).toEqual([
      'id',
      'kind',
      'name',
      'position',
      'product_id',
      'quantity',
      'sale_id',
      'service_id',
      'total_cents',
      'unit_cents',
    ]);
    expect(await columns('payments')).toContain('sale_draft');
    for (const c of ['sale_id', 'sale_total_cents', 'sale_method']) expect(await columns('appointments')).toContain(c);
    const index = async (name: string) => (await db.pool.query(`SELECT indexdef FROM pg_indexes WHERE indexname = $1`, [name])).rows[0]?.indexdef;
    expect(await index('sales_live_appointment_key')).toBe(
      'CREATE UNIQUE INDEX sales_live_appointment_key ON public.sales USING btree (appointment_id) WHERE ((appointment_id IS NOT NULL) AND (voided_at IS NULL))',
    );
    expect(await index('sales_sold_at_idx')).toBe('CREATE INDEX sales_sold_at_idx ON public.sales USING btree (sold_at)');
    expect(await index('sales_payment_intent_id_key')).toBe('CREATE UNIQUE INDEX sales_payment_intent_id_key ON public.sales USING btree (payment_intent_id)');

    // Everything below is rolled back; each refused row is tried in a savepoint.
    const client = await db.pool.connect();
    const refused = async (constraint: string, sql: string, values: unknown[] = []) => {
      await client.query('SAVEPOINT probe');
      await expect(client.query(sql, values)).rejects.toMatchObject({ constraint });
      await client.query('ROLLBACK TO SAVEPOINT probe');
    };
    try {
      await client.query('BEGIN');
      const appointment = '30000000-0000-4000-8000-000000000001';
      await client.query(
        `INSERT INTO appointments (id, offering_id, service_id, barber_id, service_name, barber_name, price_label, price_cents,
           price_kind, start_at, end_at, status, booked_by, customer_name, created_at, updated_at)
         VALUES ($1, 'x', 'haircut', 'flowxbori', 'Haircut', 'Flowxbori', '$35', 3500, 'fixed', now(), now() + interval '45 minutes',
           'booked', 'shop', 'Walk-in', now(), now())`,
        [appointment],
      );
      const sale = (id: number, fields: Record<string, unknown> = {}) => {
        const row = { appointment_id: null, method: 'cash', payment_intent_id: null, total_cents: 3500, voided_at: null, ...fields };
        return client.query(
          `INSERT INTO sales (id, barber_id, appointment_id, method, payment_intent_id, total_cents, sold_at, voided_at, created_at, updated_at)
           VALUES ($1, 'flowxbori', $2, $3, $4, $5, now(), $6, now(), now())`,
          [`31000000-0000-4000-8000-00000000000${id}`, row.appointment_id, row.method, row.payment_intent_id, row.total_cents, row.voided_at],
        );
      };
      await sale(1, { appointment_id: appointment });
      // One live sale per appointment; a voided one doesn't count.
      await refused(
        'sales_live_appointment_key',
        `INSERT INTO sales (id, barber_id, appointment_id, method, total_cents, sold_at, created_at, updated_at)
         VALUES ('31000000-0000-4000-8000-000000000009', 'flowxbori', $1, 'cash', 100, now(), now(), now())`,
        [appointment],
      );
      await sale(2, { appointment_id: appointment, voided_at: new Date() });
      // A card sale has its payment, and only a card sale does; totals stay within $10,000.
      await refused(
        'sales_card_payment',
        `INSERT INTO sales (id, barber_id, method, total_cents, sold_at, created_at, updated_at)
         VALUES ('31000000-0000-4000-8000-000000000008', 'flowxbori', 'card', 100, now(), now(), now())`,
      );
      await refused(
        'sales_total_cents_check',
        `INSERT INTO sales (id, barber_id, method, total_cents, sold_at, created_at, updated_at)
         VALUES ('31000000-0000-4000-8000-000000000008', 'flowxbori', 'cash', 1000001, now(), now(), now())`,
      );
      // Items: the total is quantity × price; services have their id, and only products a product.
      const item = (fields: string, values: string) =>
        `INSERT INTO sale_items (id, sale_id, position, ${fields}) VALUES (gen_random_uuid(), '31000000-0000-4000-8000-000000000001', ${values})`;
      await client.query(item('kind, service_id, name, quantity, unit_cents, total_cents', `0, 'service', 'haircut', 'Haircut', 1, 3500, 3500`));
      await refused('sale_items_total', item('kind, service_id, name, quantity, unit_cents, total_cents', `1, 'service', 'haircut', 'Haircut', 2, 3500, 3500`));
      await refused('sale_items_service', item('kind, name, quantity, unit_cents, total_cents', `1, 'service', 'Haircut', 1, 3500, 3500`));
      await refused('sale_items_service', item('kind, service_id, name, quantity, unit_cents, total_cents', `1, 'custom', 'haircut', 'Gift card', 1, 2500, 2500`));
      await refused(
        'sale_items_product',
        item('kind, product_id, name, quantity, unit_cents, total_cents', `1, 'custom', gen_random_uuid(), 'Gift card', 1, 2500, 2500`),
      );
      await refused(
        'sale_items_sale_id_position_key',
        item('kind, service_id, name, quantity, unit_cents, total_cents', `0, 'service', 'haircut', 'Haircut', 1, 3500, 3500`),
      );
      await refused('sale_items_quantity_check', item('kind, name, quantity, unit_cents, total_cents', `1, 'custom', 'Gift card', 100, 2500, 250000`));
      // The appointment's copy of its live sale: only on a completed appointment, and all or nothing.
      await refused(
        'appointments_sale_completed',
        `UPDATE appointments SET sale_id = '31000000-0000-4000-8000-000000000001', sale_total_cents = 3500, sale_method = 'cash' WHERE id = $1`,
        [appointment],
      );
      await client.query(
        `UPDATE appointments SET status = 'completed', sale_id = '31000000-0000-4000-8000-000000000001', sale_total_cents = 3500, sale_method = 'cash'
          WHERE id = $1`,
        [appointment],
      );
      await refused('appointments_sale', `UPDATE appointments SET sale_method = NULL WHERE id = $1`, [appointment]);
      await refused('appointments_sale_completed', `UPDATE appointments SET status = 'no_show' WHERE id = $1`, [appointment]);
      // The ticket on a payment is a JSON object.
      await refused(
        'payments_sale_draft_check',
        `INSERT INTO payments (id, amount_cents, status, created_at, updated_at, sale_draft) VALUES ('pi_probe', 500, 'requires_payment_method', now(), now(), '[1]')`,
      );
    } finally {
      await client.query('ROLLBACK').catch(() => undefined);
      client.release();
    }
  });

  it('006 keeps every row written before it valid', async () => {
    // 001–004 into a schema of its own, rows the way the server wrote them, then 006 on top.
    const dir = mkdtempSync(join(tmpdir(), 'izzy-migrations-before-006-'));
    const all = migrationFiles();
    for (const f of all.filter((f) => f.name < '006')) writeFileSync(join(dir, f.name), f.sql);
    const client = await db.pool.connect();
    try {
      await client.query('CREATE SCHEMA before_006');
      await client.query('SET search_path TO before_006, public');
      await migrate(client, pathToFileURL(`${dir}/`));
      await client.query(`INSERT INTO barbers (id, name) VALUES ('flowxbori', 'Flowxbori')`);
      await client.query(
        `INSERT INTO appointments (id, offering_id, service_id, barber_id, service_name, barber_name, price_label, price_cents,
           price_kind, start_at, end_at, status, booked_by, customer_name, payment_status, paid_cents, paid_at, created_at, updated_at)
         VALUES ('32000000-0000-4000-8000-000000000001', 'x', 'haircut', 'flowxbori', 'Haircut', 'Flowxbori', '$35', 3500, 'fixed',
           now(), now() + interval '45 minutes', 'completed', 'shop', 'Walk-in', 'paid', 3500, now(), now(), now())`,
      );
      await client.query(
        `INSERT INTO payments (id, amount_cents, appointment_id, status, created_at, updated_at)
         VALUES ('pi_before006', 3500, '32000000-0000-4000-8000-000000000001', 'succeeded', now(), now())`,
      );
      const file = all.find((f) => f.name === '006_sales.sql');
      if (!file) throw new Error('006_sales.sql is missing');
      writeFileSync(join(dir, file.name), file.sql);
      expect((await migrate(client, pathToFileURL(`${dir}/`))).applied).toEqual(['006_sales.sql']);
      const { rows } = await client.query(
        `SELECT a.status, a.payment_status, a.sale_id, a.sale_total_cents, a.sale_method, p.sale_draft
           FROM appointments a JOIN payments p ON p.appointment_id = a.id`,
      );
      expect(rows).toEqual([{ status: 'completed', payment_status: 'paid', sale_id: null, sale_total_cents: null, sale_method: null, sale_draft: null }]);
    } finally {
      await client.query('SET search_path TO public').catch(() => undefined);
      await client.query('DROP SCHEMA IF EXISTS before_006 CASCADE').catch(() => undefined);
      client.release();
    }
  });

  it('the schema has the exclusion constraint and btree_gist', async () => {
    const ext = await db.pool.query(`SELECT extname FROM pg_extension WHERE extname = 'btree_gist'`);
    expect(ext.rows).toHaveLength(1);
    const con = await db.pool.query(`SELECT pg_get_constraintdef(oid) AS def FROM pg_constraint WHERE conname = 'appointments_no_overlap'`);
    expect(con.rows[0].def).toBe(
      "EXCLUDE USING gist (barber_id WITH =, tstzrange(start_at, end_at, '[)'::text) WITH &&) WHERE (((status = 'booked'::text) OR (status = 'completed'::text)))",
    );
  });
});
