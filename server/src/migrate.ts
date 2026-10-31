import { createHash } from 'node:crypto';
import { readdirSync, readFileSync } from 'node:fs';
import type { Catalog } from './catalog.js';
import type { Queryable } from './db.js';

// Plain numbered SQL files in migrations/, each applied once in its own
// transaction and recorded in schema_migrations with a checksum. Safe to run
// again and again, and from two places at once (a transaction-scoped advisory
// lock serializes runners, which also works through a pooled connection).

export interface MigrationResult {
  applied: string[];
  skipped: string[];
}

const LOCK_KEY = 'izzy-clipz-migrations';
export const MIGRATIONS_DIR = new URL('../migrations/', import.meta.url);

export function migrationFiles(dir: URL = MIGRATIONS_DIR): { name: string; sql: string; checksum: string }[] {
  return readdirSync(dir)
    .filter((f) => /^\d{3,}_[a-z0-9_]+\.sql$/.test(f))
    .sort()
    .map((name) => {
      const sql = readFileSync(new URL(name, dir), 'utf8');
      return { name, sql, checksum: createHash('sha256').update(sql).digest('hex') };
    });
}

export async function migrate(client: Queryable, dir: URL = MIGRATIONS_DIR): Promise<MigrationResult> {
  await client.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
    version    text PRIMARY KEY,
    checksum   text NOT NULL,
    applied_at timestamptz NOT NULL DEFAULT now()
  )`);
  const result: MigrationResult = { applied: [], skipped: [] };
  for (const file of migrationFiles(dir)) {
    await client.query('BEGIN');
    try {
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [LOCK_KEY]);
      const { rows } = await client.query<{ checksum: string }>(
        'SELECT checksum FROM schema_migrations WHERE version = $1',
        [file.name],
      );
      const done = rows[0];
      if (done) {
        if (done.checksum !== file.checksum) {
          throw new Error(`${file.name} changed after it was applied. Add a new migration instead of editing it.`);
        }
        await client.query('COMMIT');
        result.skipped.push(file.name);
        continue;
      }
      await client.query(file.sql);
      await client.query('INSERT INTO schema_migrations (version, checksum) VALUES ($1, $2)', [file.name, file.checksum]);
      await client.query('COMMIT');
      result.applied.push(file.name);
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    }
  }
  return result;
}

/** Upserts the catalog's team into `barbers`; barbers no longer listed are kept (old bookings point at them) but made inactive. */
export async function seedBarbers(client: Queryable, catalog: Catalog): Promise<{ active: number; inactive: number }> {
  const ids = catalog.barbers.map((b) => b.id);
  await client.query('BEGIN');
  try {
    for (const [i, barber] of catalog.barbers.entries()) {
      await client.query(
        `INSERT INTO barbers (id, name, sort, active) VALUES ($1, $2, $3, true)
         ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, sort = EXCLUDED.sort, active = true`,
        [barber.id, barber.name, i],
      );
    }
    const { rowCount } = await client.query(
      'UPDATE barbers SET active = false WHERE active AND NOT (id = ANY($1::text[]))',
      [ids],
    );
    await client.query('COMMIT');
    return { active: ids.length, inactive: rowCount ?? 0 };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  }
}
