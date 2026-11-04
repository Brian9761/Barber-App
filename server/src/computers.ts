import { createHmac, timingSafeEqual } from 'node:crypto';
import { z } from 'zod';
import { hashManageToken, newSessionToken, ownerKeyConfigured, ownerNotConfigured, requireOwner, type ComputerSessionRow } from './auth.js';
import type { Queryable } from './db.js';
import { ApiError, json, noContent, readJsonObject } from './http.js';
import { hit, ipKey } from './ratelimit.js';
import type { Context } from './router.js';
import { formatInstant } from './time.js';
import { parse, UUID_RE } from './validation.js';

// Signing in on a computer. The owner opens the website's Business area, gets a 6-digit code
// in the Business app (Settings → Use on a computer) and types it on the website: no owner key
// is ever typed on a computer.
//
// - POST /api/owner/computer-codes (the owner key only, so a computer can't make codes): a new
//   code, good once for 10 minutes. It replaces any code before it. Only an HMAC of it, keyed
//   with the owner key, is stored, so the database alone can't tell the code.
// - POST /api/computer-sessions { code, name } (public): the code buys a session token (43
//   characters of base64url, sealed with the owner key; only its SHA-256 is stored) that works
//   like the owner key on most owner routes for 30 days (auth.ts). 10 tries per network per 10
//   minutes, and 5 wrong tries from anywhere burn the code. A new OWNER_KEY signs every computer out.
// - GET /api/owner/computer-sessions lists the computers signed in; DELETE …/:id signs one out,
//   DELETE … all of them, and DELETE …/current the computer asking (the website's Sign out).

export const CODE_MINUTES = 10;
/** Wrong tries, from any network, that burn the code. */
export const MAX_WRONG_TRIES = 5;
/** Sign-in tries per network per 10 minutes. */
export const SIGN_INS_PER_IP = 10;
export const SESSION_DAYS = 30;
/** Making a code and using one take turns, so a code is never used twice or outlives its replacement. */
const CODES_LOCK = 'izzy-clipz-computer-codes';
const NAME_MAX = 80;
/** Which owner key the sessions were made with (as a check, never the key). */
const SESSIONS_SETTINGS_KEY = 'computer_sessions';

const wrongCode = () =>
  new ApiError('wrong_code', "That code isn't right or has run out. Open Izzy Clipz Business → Settings → Use on a computer for a new one.");
const notFound = () => new ApiError('not_found', "We couldn't find that computer.");

/** The stored form of a code: HMAC-SHA256 keyed with the owner key. */
function codeHash(ownerKey: string, code: string): string {
  return createHmac('sha256', ownerKey).update(`izzy-clipz-computer-code:${code}`, 'utf8').digest('hex');
}

function codeMatches(ownerKey: string, code: string, storedHash: string): boolean {
  const given = Buffer.from(codeHash(ownerKey, code), 'hex');
  const stored = Buffer.from(storedHash, 'hex');
  return given.length === stored.length && timingSafeEqual(given, stored);
}

/** A check of the owner key: an HMAC of fixed text, which tells nothing about the key. */
function keyCheck(ownerKey: string): string {
  return createHmac('sha256', ownerKey).update('izzy-clipz-computer-sessions-key', 'utf8').digest('hex');
}

/**
 * Sessions made with an earlier owner key can't get in any more (their tokens carry its seal),
 * so they're signed out here, and the list only shows computers that still can.
 */
async function signOutOldKeys(db: Queryable, ownerKey: string, now: Date): Promise<void> {
  const check = keyCheck(ownerKey);
  const { rows } = await db.query<{ value: { keyCheck?: unknown } }>('SELECT value FROM settings WHERE key = $1', [SESSIONS_SETTINGS_KEY]);
  if (rows[0]?.value.keyCheck === check) return;
  if (rows[0]) await db.query('UPDATE computer_sessions SET revoked_at = $1 WHERE revoked_at IS NULL', [now]);
  await db.query(
    `INSERT INTO settings (key, value, updated_at) VALUES ($1, $2::jsonb, $3)
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = EXCLUDED.updated_at`,
    [SESSIONS_SETTINGS_KEY, JSON.stringify({ keyCheck: check }), now],
  );
}

/** What the website calls the computer ("Chrome on Mac"): one line of at most 80 characters, or "Computer". */
export function computerName(raw: string | null | undefined): string {
  const line = (raw ?? '').replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/g, ' ').replace(/\s+/g, ' ').trim();
  return [...line].slice(0, NAME_MAX).join('').trim() || 'Computer';
}

export function sessionJSON(row: ComputerSessionRow, currentId: string | null) {
  return {
    id: row.id,
    name: row.name,
    createdAt: formatInstant(row.created_at),
    lastUsedAt: formatInstant(row.last_used_at),
    expiresAt: formatInstant(row.expires_at),
    /** The computer asking. */
    current: row.id === currentId,
  };
}

// POST /api/owner/computer-codes

export async function createComputerCode(ctx: Context): Promise<Response> {
  await requireOwner(ctx, { keyOnly: true });
  const { deps } = ctx;
  const ownerKey = deps.config.ownerKey;
  if (!ownerKey) throw ownerNotConfigured();
  const code = deps.computerCode();
  if (!/^\d{6}$/.test(code)) throw new Error('computerCode() must make 6 digits');
  const now = deps.now();
  const expiresAt = new Date(now.getTime() + CODE_MINUTES * 60_000);
  await deps.db.transaction(async (tx) => {
    await tx.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [CODES_LOCK]);
    // One code at a time: a new one replaces every code before it, used or not.
    await tx.query('DELETE FROM computer_codes');
    await tx.query('INSERT INTO computer_codes (id, code_hash, created_at, expires_at) VALUES ($1, $2, $3, $4)', [
      deps.uuid(),
      codeHash(ownerKey, code),
      now,
      expiresAt,
    ]);
  });
  return json({ code, expiresAt: formatInstant(expiresAt), expiresInSeconds: CODE_MINUTES * 60 }, 201);
}

// POST /api/computer-sessions { code, name }

const signInBody = z.object({
  code: z
    .string({ error: 'Type the 6-digit code from Izzy Clipz Business.' })
    .max(40, { error: "That code isn't right or has run out. Open Izzy Clipz Business → Settings → Use on a computer for a new one." }),
  // Longer names are cut to 80 characters; this only turns away what can't be a name.
  name: z.string({ error: 'name must be text.' }).max(500, { error: 'That computer name is too long.' }).nullish(),
});

export async function createComputerSession(ctx: Context): Promise<Response> {
  const { deps, request } = ctx;
  const config = deps.config;
  // No owner key, no codes: the Business area stays closed, like the owner routes.
  if (!ownerKeyConfigured(config)) throw ownerNotConfigured();
  const ownerKey = config.ownerKey;
  const body = parse(signInBody, await readJsonObject(request));
  const hits = await hit(deps.db, ipKey('computer-sign-in', deps.clientIp(request)), deps.now(), { max: SIGN_INS_PER_IP, windowMinutes: 10 });
  if (hits > SIGN_INS_PER_IP) {
    throw new ApiError('rate_limited', 'Too many tries from this network. Wait 10 minutes, then try a new code from Izzy Clipz Business.', {
      headers: { 'retry-after': '600' },
    });
  }
  // People type "483 920" or "483-920".
  const code = body.code.replace(/[\s-]/g, '');
  const now = deps.now();
  const signedIn = await deps.db.transaction(async (tx) => {
    await tx.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [CODES_LOCK]);
    const { rows } = await tx.query<{ id: string; code_hash: string }>(
      `SELECT id, code_hash FROM computer_codes
        WHERE used_at IS NULL AND expires_at > $1 AND failed_attempts < $2
        ORDER BY created_at DESC LIMIT 1
        FOR UPDATE`,
      [now, MAX_WRONG_TRIES],
    );
    const active = rows[0];
    // Something that isn't 6 digits can't be the code, so it isn't counted against it.
    if (!active || !/^\d{6}$/.test(code)) return null;
    if (!codeMatches(ownerKey, code, active.code_hash)) {
      // Counted on the code itself, from any network: the 5th wrong try burns it.
      await tx.query('UPDATE computer_codes SET failed_attempts = failed_attempts + 1 WHERE id = $1', [active.id]);
      return null;
    }
    await tx.query('UPDATE computer_codes SET used_at = $2 WHERE id = $1', [active.id, now]);
    await signOutOldKeys(tx, ownerKey, now);
    // Sessions that ended (signed out or expired) aren't kept.
    await tx.query('DELETE FROM computer_sessions WHERE revoked_at IS NOT NULL OR expires_at <= $1', [now]);
    // From 32 fresh random bytes (made like a manage token), sealed with the owner key.
    const token = newSessionToken(ownerKey, Buffer.from(deps.manageToken(), 'base64url'));
    const { rows: created } = await tx.query<ComputerSessionRow>(
      `INSERT INTO computer_sessions (id, token_hash, name, created_at, last_used_at, expires_at)
       VALUES ($1, $2, $3, $4, $4, $5)
       RETURNING *`,
      [deps.uuid(), hashManageToken(token), computerName(body.name), now, new Date(now.getTime() + SESSION_DAYS * 24 * 60 * 60_000)],
    );
    const session = created[0];
    return session ? { token, session } : null;
  });
  if (!signedIn) throw wrongCode();
  return json({ token: signedIn.token, session: sessionJSON(signedIn.session, signedIn.session.id) }, 201);
}

// GET /api/owner/computer-sessions

export async function listComputerSessions(ctx: Context): Promise<Response> {
  const auth = await requireOwner(ctx);
  await signOutOldKeys(ctx.deps.db, ctx.deps.config.ownerKey ?? '', ctx.deps.now());
  const { rows } = await ctx.deps.db.query<ComputerSessionRow>(
    `SELECT * FROM computer_sessions
      WHERE revoked_at IS NULL AND expires_at > $1
      ORDER BY last_used_at DESC, created_at DESC, id`,
    [ctx.deps.now()],
  );
  const current = auth.kind === 'computer' ? auth.session.id : null;
  return json({ sessions: rows.map((row) => sessionJSON(row, current)) });
}

// DELETE /api/owner/computer-sessions/:id, DELETE /api/owner/computer-sessions, DELETE /api/owner/computer-sessions/current

export async function revokeComputerSession(ctx: Context): Promise<Response> {
  await requireOwner(ctx);
  const id = ctx.params.id ?? '';
  if (!UUID_RE.test(id)) throw notFound();
  const { rowCount } = await ctx.deps.db.query('UPDATE computer_sessions SET revoked_at = COALESCE(revoked_at, $2) WHERE id = $1', [
    id,
    ctx.deps.now(),
  ]);
  if (!rowCount) throw notFound();
  return noContent();
}

export async function revokeAllComputerSessions(ctx: Context): Promise<Response> {
  await requireOwner(ctx);
  await ctx.deps.db.query('UPDATE computer_sessions SET revoked_at = $1 WHERE revoked_at IS NULL', [ctx.deps.now()]);
  return noContent();
}

export async function revokeCurrentComputerSession(ctx: Context): Promise<Response> {
  const auth = await requireOwner(ctx);
  if (auth.kind !== 'computer') throw new ApiError('invalid_request', 'Only a computer that is signed in can sign itself out.');
  await ctx.deps.db.query('UPDATE computer_sessions SET revoked_at = COALESCE(revoked_at, $2) WHERE id = $1', [auth.session.id, ctx.deps.now()]);
  return noContent();
}
