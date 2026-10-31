// npm run migrate: applies migrations/*.sql and seeds barbers from data/catalog.json.
// Uses DATABASE_URL_UNPOOLED (direct connection, as Neon recommends for schema
// changes), falling back to DATABASE_URL.
import { existsSync } from 'node:fs';
import pg from 'pg';
import { loadCatalog } from '../src/catalog.js';
import { normalizeConnectionString } from '../src/db.js';
import { migrate, seedBarbers } from '../src/migrate.js';

// `vercel env pull .env.local` writes the Neon URLs here; real environment variables win.
if (!process.env.DATABASE_URL_UNPOOLED && !process.env.DATABASE_URL && existsSync('.env.local')) {
  process.loadEnvFile('.env.local');
}

const url = process.env.DATABASE_URL_UNPOOLED || process.env.DATABASE_URL;
if (!url) {
  console.error('Set DATABASE_URL_UNPOOLED (or DATABASE_URL), or pull them with `vercel env pull .env.local`.');
  process.exit(1);
}

const client = new pg.Client({ connectionString: normalizeConnectionString(url) });
await client.connect();
try {
  const { applied, skipped } = await migrate(client);
  for (const name of skipped) console.log(`  already applied  ${name}`);
  for (const name of applied) console.log(`  applied          ${name}`);
  const team = await seedBarbers(client, loadCatalog());
  console.log(`Migrations up to date (${applied.length} new). Barbers: ${team.active} active, ${team.inactive} retired.`);
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
} finally {
  await client.end();
}
