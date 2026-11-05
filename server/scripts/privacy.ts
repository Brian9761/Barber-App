// npm run privacy:find | privacy:correct | privacy:forget: answering a client's privacy request
// (src/privacy.ts says what each does). Uses DATABASE_URL (or DATABASE_URL_UNPOOLED), and the
// Stripe settings to delete saved cards, like the server.
import { existsSync, writeFileSync } from 'node:fs';
import { createPool, poolDb } from '../src/db.js';
import { privacyCommand } from '../src/privacy.js';
import { productionDeps } from '../src/production.js';

// `vercel env pull .env.local` writes the settings here; real environment variables win.
if (existsSync('.env.local')) process.loadEnvFile('.env.local');

const url = process.env.DATABASE_URL || process.env.DATABASE_URL_UNPOOLED;
if (!url) {
  console.error('Set DATABASE_URL (or DATABASE_URL_UNPOOLED), or pull it with `vercel env pull .env.local`.');
  process.exit(1);
}

const pool = createPool(url, { max: 1 });
try {
  const result = await privacyCommand(process.argv.slice(2), { ...productionDeps(), db: poolDb(pool) });
  if (result.file) writeFileSync(result.file.path, result.file.text, { mode: 0o600 });
  (result.exitCode === 0 ? console.log : console.error)(result.output);
  process.exitCode = result.exitCode;
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
} finally {
  await pool.end();
}
