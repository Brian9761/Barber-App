import { randomBytes } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';
import { btree_gist } from '@electric-sql/pglite/contrib/btree_gist';
import { PGLiteSocketServer } from '@electric-sql/pglite-socket';
import pg from 'pg';
import { loadCatalog } from '../../src/catalog.js';
import { createPool } from '../../src/db.js';
import { migrate, seedBarbers } from '../../src/migrate.js';

// A database for one test file. By default: PGlite (Postgres 18 in WASM) with
// btree_gist, served over the Postgres wire protocol by pglite-socket, so the
// production `pg` Pool code runs unchanged. PGlite has a single session, so the
// pool has one connection and concurrent requests queue for it.
//
// Set TEST_DATABASE_URL (a role that may CREATE DATABASE) to run the same tests
// against a real Postgres instead: each file gets its own throwaway database
// and a pool of 5, so concurrent transactions really race.

export interface TestDatabase {
  kind: 'pglite' | 'postgres';
  url: string;
  pool: pg.Pool;
  reset(): Promise<void>;
  close(): Promise<void>;
}

const TABLES = ['payments', 'appointments', 'time_off', 'products', 'rate_limits', 'api_usage', 'yelp_cache'];

async function prepare(pool: pg.Pool): Promise<void> {
  const client = await pool.connect();
  try {
    await migrate(client);
    await seedBarbers(client, loadCatalog());
  } finally {
    client.release();
  }
}

function withDatabase(url: string, database: string): string {
  const u = new URL(url);
  u.pathname = `/${database}`;
  return u.toString();
}

export async function startTestDatabase(): Promise<TestDatabase> {
  const external = process.env.TEST_DATABASE_URL;
  if (external) {
    const name = `izzy_test_${randomBytes(6).toString('hex')}`;
    const admin = new pg.Client({ connectionString: external });
    await admin.connect();
    await admin.query(`CREATE DATABASE ${name}`);
    await admin.end();
    const url = withDatabase(external, name);
    const pool = createPool(url, { max: 5 });
    await prepare(pool);
    return {
      kind: 'postgres',
      url,
      pool,
      reset: async () => {
        await pool.query(`TRUNCATE ${TABLES.join(', ')}`);
      },
      close: async () => {
        await pool.end();
        const cleanup = new pg.Client({ connectionString: external });
        await cleanup.connect();
        await cleanup.query(`DROP DATABASE IF EXISTS ${name} WITH (FORCE)`);
        await cleanup.end();
      },
    };
  }

  const db = await PGlite.create({ extensions: { btree_gist } });
  // pg-pool drops a connection after a failed query and opens a new one; allow a
  // few sockets so the reconnect isn't refused while the old one is still closing.
  // The pool itself never holds more than one at a time.
  const server = new PGLiteSocketServer({ db, host: '127.0.0.1', port: 0, maxConnections: 4 });
  await server.start();
  const url = `postgres://postgres@${server.getServerConn()}/postgres`;
  const pool = createPool(url, { max: 1 });
  await prepare(pool);
  return {
    kind: 'pglite',
    url,
    pool,
    reset: async () => {
      await pool.query(`TRUNCATE ${TABLES.join(', ')}`);
    },
    close: async () => {
      await pool.end();
      await server.stop();
      await db.close();
    },
  };
}
