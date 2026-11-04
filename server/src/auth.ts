import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { MIN_OWNER_KEY_LENGTH, type Config } from './config.js';
import type { Deps } from './deps.js';
import { ApiError } from './http.js';

const sha256 = (text: string): Buffer => createHash('sha256').update(text, 'utf8').digest();

/** The secret in `Authorization: Bearer <secret>`, or null. */
function bearerToken(header: string | null): string | null {
  if (!header) return null;
  const match = /^Bearer[ ]+(.+)$/i.exec(header.trim());
  return match?.[1] ?? null;
}

/** Constant-time check of `Authorization: Bearer <secret>`, comparing SHA-256 digests. */
export function bearerMatches(header: string | null, expected: string | undefined): boolean {
  const token = bearerToken(header);
  if (!expected || !token) return false;
  return timingSafeEqual(sha256(token), sha256(expected));
}

/** Whether the server has an owner key long enough to open the owner routes. */
export function ownerKeyConfigured(config: Pick<Config, 'ownerKey'>): config is { ownerKey: string } {
  return Boolean(config.ownerKey && config.ownerKey.length >= MIN_OWNER_KEY_LENGTH);
}

export const ownerNotConfigured = () => new ApiError('owner_not_configured', "The shop's owner key isn't set up on the server yet.");

/** A computer signed in to the website's Business area (migrations/005). */
export interface ComputerSessionRow {
  id: string;
  token_hash: string;
  name: string;
  created_at: Date;
  last_used_at: Date;
  expires_at: Date;
  revoked_at: Date | null;
}

/** Who is calling an owner route: the owner key (the Business app), or a computer signed in with a code. */
export type OwnerAuth = { kind: 'key' } | { kind: 'computer'; session: ComputerSessionRow };

/** A session's `last_used_at` is written at most this often, so every request isn't a write. */
export const SESSION_TOUCH_MINUTES = 10;

/** The live session (not revoked, not expired) for a computer's token, marked as used. */
async function sessionForToken(deps: Pick<Deps, 'db' | 'now'>, token: string): Promise<ComputerSessionRow | null> {
  const now = deps.now();
  const { rows } = await deps.db.query<ComputerSessionRow>(
    'SELECT * FROM computer_sessions WHERE token_hash = $1 AND revoked_at IS NULL AND expires_at > $2',
    [hashManageToken(token), now],
  );
  const session = rows[0];
  if (!session) return null;
  if (now.getTime() - session.last_used_at.getTime() >= SESSION_TOUCH_MINUTES * 60_000) {
    await deps.db.query('UPDATE computer_sessions SET last_used_at = $2 WHERE id = $1 AND last_used_at < $2', [session.id, now]);
    session.last_used_at = now;
  }
  return session;
}

/**
 * Owner routes: 503 until a long enough OWNER_KEY is set; then `Authorization: Bearer` with the
 * owner key, or with the token of a computer signed in with a code (computers.ts), or 401.
 * `keyOnly` routes (Tap to Pay, codes for a computer, disconnecting Stripe) turn a computer
 * down with 403: only the Business app on the owner's iPhone may do those.
 */
export async function requireOwner(
  ctx: { request: Request; deps: Pick<Deps, 'config' | 'db' | 'now'> },
  options: { keyOnly?: boolean } = {},
): Promise<OwnerAuth> {
  const { config } = ctx.deps;
  if (!ownerKeyConfigured(config)) throw ownerNotConfigured();
  const header = ctx.request.headers.get('authorization');
  if (bearerMatches(header, config.ownerKey)) return { kind: 'key' };
  const token = bearerToken(header);
  const session = token && isWellFormedManageToken(token) ? await sessionForToken(ctx.deps, token) : null;
  if (!session) {
    throw new ApiError('unauthorized', "That owner key isn't right. Check it and sign in again.", {
      headers: { 'www-authenticate': 'Bearer' },
    });
  }
  if (options.keyOnly) throw new ApiError('forbidden', 'This can only be done in the Izzy Clipz Business app on your iPhone.');
  return { kind: 'computer', session };
}

/** The cron route accepts only Vercel Cron's `Authorization: Bearer <CRON_SECRET>`. */
export function requireCron(request: Request, config: Config): void {
  if (!bearerMatches(request.headers.get('authorization'), config.cronSecret)) {
    throw new ApiError('unauthorized', 'Not allowed.');
  }
}

// Manage tokens: 32 random bytes, base64url (43 characters). Only the SHA-256
// digest is stored, so a database leak doesn't let anyone cancel bookings.

const TOKEN_RE = /^[A-Za-z0-9_-]{43}$/;

export function newManageToken(): string {
  return randomBytes(32).toString('base64url');
}

export function hashManageToken(token: string): string {
  return sha256(token).toString('hex');
}

export function isWellFormedManageToken(token: string): boolean {
  return TOKEN_RE.test(token);
}

/**
 * A token the app made itself for `POST /api/appointments` (`X-Manage-Token`):
 * exactly what `newManageToken` makes, 32 bytes in canonical base64url (so the
 * last character's two unused bits are zero). Anything else is turned down.
 */
export function isNewManageToken(token: string): boolean {
  return TOKEN_RE.test(token) && Buffer.from(token, 'base64url').toString('base64url') === token;
}

/** Constant-time comparison of a presented token with a stored digest. */
export function manageTokenMatches(token: string, storedHash: string | null): boolean {
  if (!storedHash || !/^[0-9a-f]{64}$/.test(storedHash) || !isWellFormedManageToken(token)) return false;
  return timingSafeEqual(sha256(token), Buffer.from(storedHash, 'hex'));
}
