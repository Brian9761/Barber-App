import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { MIN_OWNER_KEY_LENGTH, type Config } from './config.js';
import { ApiError } from './http.js';

const sha256 = (text: string): Buffer => createHash('sha256').update(text, 'utf8').digest();

/** Constant-time check of `Authorization: Bearer <secret>`, comparing SHA-256 digests. */
export function bearerMatches(header: string | null, expected: string | undefined): boolean {
  if (!expected || !header) return false;
  const match = /^Bearer[ ]+(.+)$/i.exec(header.trim());
  if (!match?.[1]) return false;
  return timingSafeEqual(sha256(match[1]), sha256(expected));
}

/** Owner routes: 503 until a long enough OWNER_KEY is set, then 401 without it. */
export function requireOwner(request: Request, config: Config): void {
  const key = config.ownerKey;
  if (!key || key.length < MIN_OWNER_KEY_LENGTH) {
    throw new ApiError('owner_not_configured', "The shop's owner key isn't set up on the server yet.");
  }
  if (!bearerMatches(request.headers.get('authorization'), key)) {
    throw new ApiError('unauthorized', "That owner key isn't right. Check it and sign in again.", {
      headers: { 'www-authenticate': 'Bearer' },
    });
  }
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

/** Constant-time comparison of a presented token with a stored digest. */
export function manageTokenMatches(token: string, storedHash: string | null): boolean {
  if (!storedHash || !/^[0-9a-f]{64}$/.test(storedHash) || !isWellFormedManageToken(token)) return false;
  return timingSafeEqual(sha256(token), Buffer.from(storedHash, 'hex'));
}
