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
    expect(rows[0].version).toBe('001_init.sql');
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
    writeFileSync(join(dir, '002_extra.sql'), 'CREATE TABLE migration_probe (id int);');
    writeFileSync(join(dir, 'notes.txt'), 'ignored');
    const url = pathToFileURL(`${dir}/`);
    const client = await db.pool.connect();
    try {
      expect((await migrate(client, url)).applied).toEqual(['002_extra.sql']);
      expect((await migrate(client, url)).applied).toEqual([]);
      writeFileSync(join(dir, '002_extra.sql'), 'CREATE TABLE migration_probe (id bigint);');
      await expect(migrate(client, url)).rejects.toThrow('002_extra.sql changed after it was applied');
      // The failed run left nothing half-done.
      expect((await client.query(`SELECT count(*)::int AS n FROM schema_migrations`)).rows[0].n).toBe(2);
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

  it('the schema has the exclusion constraint and btree_gist', async () => {
    const ext = await db.pool.query(`SELECT extname FROM pg_extension WHERE extname = 'btree_gist'`);
    expect(ext.rows).toHaveLength(1);
    const con = await db.pool.query(`SELECT pg_get_constraintdef(oid) AS def FROM pg_constraint WHERE conname = 'appointments_no_overlap'`);
    expect(con.rows[0].def).toBe(
      "EXCLUDE USING gist (barber_id WITH =, tstzrange(start_at, end_at, '[)'::text) WITH &&) WHERE (((status = 'booked'::text) OR (status = 'completed'::text)))",
    );
  });
});
