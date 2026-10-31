import pg from 'pg';

// node-postgres over TCP with a small pool, as Neon recommends for Vercel Fluid
// compute. Inside a transaction, every query must go through the transaction's
// client: the pool may have a single connection (tests use max 1).

export interface Queryable {
  query<R extends pg.QueryResultRow = pg.QueryResultRow>(text: string, values?: unknown[]): Promise<pg.QueryResult<R>>;
}

export interface Db extends Queryable {
  /** Runs `fn` in BEGIN … COMMIT on one connection; rolls back if it throws. */
  transaction<T>(fn: (client: Queryable) => Promise<T>): Promise<T>;
}

// `date` columns as plain "YYYY-MM-DD" strings, never local-time Dates.
pg.types.setTypeParser(pg.types.builtins.DATE, (value: string) => value);

/** Neon URLs say `sslmode=require`; pg treats that as verify-full but logs a warning. Say it explicitly. */
export function normalizeConnectionString(url: string): string {
  return url.replace(/([?&])sslmode=require(?=&|$)/, '$1sslmode=verify-full');
}

export function createPool(connectionString: string, options: { max?: number } = {}): pg.Pool {
  const pool = new pg.Pool({
    connectionString: normalizeConnectionString(connectionString),
    max: options.max ?? 5,
    min: options.max === 1 ? 0 : 1,
    idleTimeoutMillis: 5_000,
    connectionTimeoutMillis: 10_000,
  });
  // The database can close a connection the pool is keeping idle (Neon does when
  // it scales down or restarts). The pool drops that connection and opens a new
  // one when it's needed; without a listener, node would treat the event as an
  // uncaught error and stop the whole server.
  pool.on('error', (error: Error & { code?: string }) => {
    console.error('A database connection the pool was keeping closed; the next query opens a new one', {
      code: error.code,
      message: error.message,
    });
  });
  return pool;
}

export function poolDb(pool: pg.Pool): Db {
  return {
    query: (text, values) => pool.query(text, values),
    async transaction(fn) {
      const client = await pool.connect();
      let broken: Error | undefined;
      try {
        await client.query('BEGIN');
        const result = await fn(client);
        await client.query('COMMIT');
        return result;
      } catch (error) {
        try {
          await client.query('ROLLBACK');
        } catch (rollbackError) {
          // Don't hand a connection in an unknown state back to the pool.
          broken = rollbackError instanceof Error ? rollbackError : new Error(String(rollbackError));
        }
        throw error;
      } finally {
        client.release(broken);
      }
    },
  };
}

/** Postgres error helpers. */
export function pgErrorCode(error: unknown): string | undefined {
  return typeof error === 'object' && error !== null && 'code' in error && typeof error.code === 'string'
    ? error.code
    : undefined;
}

export const EXCLUSION_VIOLATION = '23P01';
export const UNIQUE_VIOLATION = '23505';
export const DEADLOCK_DETECTED = '40P01';

/**
 * Two transactions writing overlapping appointments at the same moment can each
 * wait for the other inside the exclusion constraint's check; Postgres then
 * aborts one with a deadlock. Bookings lock their barbers first so that doesn't
 * happen between them, but whichever way it happens, the loser lost the time.
 */
export function isOverlapConflict(error: unknown): boolean {
  const code = pgErrorCode(error);
  return code === EXCLUSION_VIOLATION || code === DEADLOCK_DETECTED;
}

/** The constraint or index a Postgres error names, if any. */
export function pgConstraint(error: unknown): string | undefined {
  return typeof error === 'object' && error !== null && 'constraint' in error && typeof error.constraint === 'string'
    ? error.constraint
    : undefined;
}
