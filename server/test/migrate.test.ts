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
      '005_stripe_connect_and_computers.sql',
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
      // 005: the connected Stripe account the card is saved on.
      'stripe_account_id',
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

  it('005 adds the Stripe Connect states, the accounts cards and payments live on, and computer sign-in (hashes only)', async () => {
    const columns = async (table: string) =>
      (
        await db.pool.query(
          `SELECT column_name, data_type, is_nullable FROM information_schema.columns WHERE table_name = $1 ORDER BY column_name`,
          [table],
        )
      ).rows.map((r) => `${r.column_name} ${r.data_type}${r.is_nullable === 'YES' ? ' null' : ''}`);
    expect(await columns('stripe_connect_states')).toEqual([
      'created_at timestamp with time zone',
      'expires_at timestamp with time zone',
      'return_to text',
      'state_hash text',
    ]);
    expect(await columns('computer_codes')).toEqual([
      'code_hash text',
      'created_at timestamp with time zone',
      'expires_at timestamp with time zone',
      'failed_attempts integer',
      'id uuid',
      'used_at timestamp with time zone null',
    ]);
    expect(await columns('computer_sessions')).toEqual([
      'created_at timestamp with time zone',
      'expires_at timestamp with time zone',
      'id uuid',
      'last_used_at timestamp with time zone',
      'name text',
      'revoked_at timestamp with time zone null',
      'token_hash text',
    ]);
    for (const table of ['saved_cards', 'payments']) {
      expect(await columns(table), table).toContain('stripe_account_id text null');
    }
    const client = await db.pool.connect();
    const rejects = async (sql: string) => {
      await client.query('SAVEPOINT probe');
      await expect(client.query(sql), sql).rejects.toThrow();
      await client.query('ROLLBACK TO SAVEPOINT probe');
    };
    try {
      await client.query('BEGIN');
      const hash = 'a'.repeat(64);
      // Rows from before 005 stay valid: no account means the server's own key.
      await client.query(
        `INSERT INTO saved_cards (id, token_hash, checkout_session_id, stripe_customer_id, stripe_payment_method_id, brand, last4, exp_month, exp_year, livemode, created_at)
         VALUES (gen_random_uuid(), $1, 'cs_test_old', 'cus_old', 'pm_old', 'visa', '4242', 1, 2030, false, now())`,
        [hash],
      );
      await client.query(`INSERT INTO payments (id, amount_cents, status, created_at, updated_at) VALUES ('pi_old', 500, 'succeeded', now(), now())`);
      expect((await client.query(`SELECT stripe_account_id FROM payments WHERE id = 'pi_old'`)).rows).toEqual([{ stripe_account_id: null }]);
      await client.query(`UPDATE payments SET stripe_account_id = 'acct_1Shop' WHERE id = 'pi_old'`);
      await rejects(`UPDATE payments SET stripe_account_id = 'not-an-account' WHERE id = 'pi_old'`);
      await rejects(`UPDATE saved_cards SET stripe_account_id = 'acct_' WHERE checkout_session_id = 'cs_test_old'`);
      // States: hashes only, a known way back, and an expiry after they were made.
      await client.query(`INSERT INTO stripe_connect_states VALUES ($1, 'web', now(), now() + interval '1 hour')`, [hash]);
      await rejects(`INSERT INTO stripe_connect_states VALUES ('raw-state', 'app', now(), now() + interval '1 hour')`);
      await rejects(`INSERT INTO stripe_connect_states VALUES ('${'b'.repeat(64)}', 'email', now(), now() + interval '1 hour')`);
      await rejects(`INSERT INTO stripe_connect_states VALUES ('${'c'.repeat(64)}', 'app', now(), now())`);
      // Codes: a hash, never the 6 digits.
      await client.query(`INSERT INTO computer_codes (id, code_hash, created_at, expires_at) VALUES (gen_random_uuid(), $1, now(), now() + interval '10 minutes')`, [hash]);
      expect((await client.query('SELECT failed_attempts, used_at FROM computer_codes')).rows).toEqual([{ failed_attempts: 0, used_at: null }]);
      await rejects(`INSERT INTO computer_codes (id, code_hash, created_at, expires_at) VALUES (gen_random_uuid(), '483920', now(), now() + interval '10 minutes')`);
      // Sessions: a unique token hash and a name of 1–80 characters.
      const session = (token: string, name: string) =>
        `INSERT INTO computer_sessions (id, token_hash, name, created_at, last_used_at, expires_at)
         VALUES (gen_random_uuid(), '${token}', '${name}', now(), now(), now() + interval '30 days')`;
      await client.query(session(hash, 'Chrome on Mac'));
      await rejects(session(hash, 'Another computer'));
      await rejects(session('d'.repeat(64), ''));
      await rejects(session('e'.repeat(64), 'x'.repeat(81)));
      await rejects(session('fixture-session-token', 'Chrome on Mac'));
    } finally {
      await client.query('ROLLBACK');
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
