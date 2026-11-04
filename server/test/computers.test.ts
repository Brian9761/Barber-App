import { createHash } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { computerName, MAX_WRONG_TRIES, SIGN_INS_PER_IP } from '../src/computers.js';
import { RESPONSES } from './helpers/contract.js';
import { OWNER_KEY, useHarness } from './helpers/harness.js';

// Signing in on a computer with a 6-digit code from the Business app: the code (once, 10
// minutes, burned after 5 wrong tries, replaced by the next one), the session it buys (30
// days, works like the owner key on most owner routes), and signing out.

// Monday Nov 2 2026, 10:00 AM PST.
const h = useHarness({ now: '2026-11-02T18:00:00Z' });
const owner = { owner: true } as const;
const sha256 = (text: string) => createHash('sha256').update(text).digest('hex');

const newCode = async (): Promise<string> => {
  const res = await h.call('POST', '/api/owner/computer-codes', owner);
  expect(res.status, res.text).toBe(201);
  return res.body.code;
};
const signIn = (code: unknown, name: unknown = 'Chrome on Mac', ip = '203.0.113.40') =>
  h.call('POST', '/api/computer-sessions', { body: { code, name }, ip });
const as = (token: string) => ({ headers: { authorization: `Bearer ${token}` } });
async function session(name = 'Chrome on Mac', ip?: string): Promise<{ token: string; id: string }> {
  const res = await signIn(await newCode(), name, ip);
  expect(res.status, res.text).toBe(201);
  return { token: res.body.token, id: res.body.session.id };
}
const wrongCode = {
  code: 'wrong_code',
  message: "That code isn't right or has run out. Open Izzy Clipz Business → Settings → Use on a computer for a new one.",
};

describe('POST /api/owner/computer-codes', () => {
  it('gives a 6-digit code for 10 minutes; only a keyed hash of it is stored', async () => {
    const res = await h.call('POST', '/api/owner/computer-codes', owner);
    expect(res.status).toBe(201);
    expect(res.body).toEqual({ code: '483920', expiresAt: '2026-11-02T18:10:00Z', expiresInSeconds: 600 });
    expect(RESPONSES['computer-code'].safeParse(res.body).success).toBe(true);
    const { rows } = await h.database.pool.query('SELECT * FROM computer_codes');
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ used_at: null, failed_attempts: 0, expires_at: new Date('2026-11-02T18:10:00Z') });
    expect(rows[0].code_hash).toMatch(/^[0-9a-f]{64}$/);
    // Not the code, and not its plain SHA-256 either (a million guesses would find that).
    expect(rows[0].code_hash).not.toBe(sha256('483920'));
    expect(JSON.stringify(rows)).not.toContain('483920');
  });

  it('only with the owner key: a computer can’t make codes', async () => {
    const computer = await session();
    const res = await h.call('POST', '/api/owner/computer-codes', as(computer.token));
    expect(res.status).toBe(403);
    expect(res.body.error).toEqual({ code: 'forbidden', message: 'This can only be done in the Izzy Clipz Business app on your iPhone.' });
    expect((await h.call('POST', '/api/owner/computer-codes')).status).toBe(401);
  });

  it('a new code replaces the one before it', async () => {
    const first = await newCode();
    const second = await newCode();
    expect(second).not.toBe(first);
    expect((await signIn(first)).body.error).toEqual(wrongCode);
    expect((await signIn(second)).status).toBe(201);
    expect((await h.database.pool.query('SELECT count(*)::int AS n FROM computer_codes')).rows[0].n).toBe(1);
  });
});

describe('POST /api/computer-sessions (typing the code on the computer)', () => {
  it('the right code gives a session token (only its SHA-256 is stored) for 30 days', async () => {
    const code = await newCode();
    const res = await signIn(code, 'Chrome on Mac');
    expect(res.status, res.text).toBe(201);
    expect(RESPONSES['computer-session-created'].safeParse(res.body).success).toBe(true);
    expect(res.body.session).toEqual({
      id: res.body.session.id,
      name: 'Chrome on Mac',
      createdAt: '2026-11-02T18:00:00Z',
      lastUsedAt: '2026-11-02T18:00:00Z',
      expiresAt: '2026-12-02T18:00:00Z',
      current: true,
    });
    const { rows } = await h.database.pool.query('SELECT * FROM computer_sessions');
    expect(rows).toHaveLength(1);
    expect(rows[0].token_hash).toBe(sha256(res.body.token));
    expect(JSON.stringify(rows)).not.toContain(res.body.token);
    // The token works on owner routes.
    expect((await h.call('GET', '/api/owner/appointments', as(res.body.token))).status).toBe(200);
  });

  it('a code works once', async () => {
    const code = await newCode();
    expect((await signIn(code)).status).toBe(201);
    const again = await signIn(code, 'Firefox on Linux', '203.0.113.41');
    expect(again.status).toBe(400);
    expect(again.body.error).toEqual(wrongCode);
  });

  it('a code runs out after 10 minutes', async () => {
    const code = await newCode();
    h.advance(9);
    const late = await newCode();
    h.advance(9);
    expect((await signIn(late)).status).toBe(201);
    const code2 = await newCode();
    h.advance(10);
    expect((await signIn(code2)).body.error).toEqual(wrongCode);
    expect(code).not.toBe(code2);
  });

  it('spaces and dashes in the code are ignored', async () => {
    for (const typed of [(c: string) => `${c.slice(0, 3)} ${c.slice(3)}`, (c: string) => `${c.slice(0, 3)}-${c.slice(3)}`, (c: string) => ` ${c} `]) {
      const code = await newCode();
      const res = await signIn(typed(code), 'Safari on Mac', `198.51.100.${code.slice(0, 2)}`);
      expect(res.status, typed(code)).toBe(201);
    }
  });

  it('5 wrong tries, from any networks, burn the code', async () => {
    const code = await newCode();
    const wrong = code === '111111' ? '222222' : '111111';
    for (let i = 0; i < MAX_WRONG_TRIES; i++) {
      const res = await signIn(wrong, 'Guess', `192.0.2.${10 + i}`);
      expect(res.status).toBe(400);
      expect(res.body.error).toEqual(wrongCode);
    }
    expect((await signIn(code, 'Chrome on Mac', '192.0.2.99')).body.error).toEqual(wrongCode);
    expect((await h.database.pool.query('SELECT failed_attempts FROM computer_codes')).rows[0].failed_attempts).toBe(MAX_WRONG_TRIES);
    // A new code works.
    expect((await signIn(await newCode(), 'Chrome on Mac', '192.0.2.99')).status).toBe(201);
  });

  it('4 wrong tries don’t; typing something that isn’t 6 digits isn’t counted', async () => {
    const code = await newCode();
    const wrong = code === '111111' ? '222222' : '111111';
    for (let i = 0; i < MAX_WRONG_TRIES - 1; i++) await signIn(wrong, 'Guess', `192.0.2.${10 + i}`);
    for (const typo of ['48392', '4839200', 'abcdef', '']) {
      const res = await signIn(typo, 'Typo', '192.0.2.50');
      expect(res.status, typo).toBe(400);
      expect(res.body.error).toEqual(wrongCode);
    }
    expect((await signIn(code, 'Chrome on Mac', '192.0.2.51')).status).toBe(201);
  });

  it('10 tries per network per 10 minutes, then a plain 429', async () => {
    await newCode();
    for (let i = 0; i < SIGN_INS_PER_IP; i++) expect((await signIn('000000', 'Guess')).status).toBe(400);
    const limited = await signIn('000000', 'Guess');
    expect(limited.status).toBe(429);
    expect(limited.body.error).toEqual({
      code: 'rate_limited',
      message: 'Too many tries from this network. Wait 10 minutes, then try a new code from Izzy Clipz Business.',
    });
    expect(limited.headers.get('retry-after')).toBe('600');
    // Even the right code waits.
    const code = await newCode();
    expect((await signIn(code)).status).toBe(429);
    expect((await signIn(code, 'Chrome on Mac', '203.0.113.99')).status).toBe(201);
    h.advance(11);
    expect((await signIn(await newCode())).status).toBe(201);
  });

  it('wants the code as text; the name is tidied up, and "Computer" when there’s none', async () => {
    await newCode();
    expect((await signIn(483920)).status).toBe(400);
    expect((await h.call('POST', '/api/computer-sessions', { body: { name: 'x' } })).status).toBe(400);
    expect((await signIn('1'.repeat(41))).body.error.code).toBe('invalid_request');
    expect((await signIn(await newCode(), null, '198.51.100.60')).body.session.name).toBe('Computer');
    expect((await signIn(await newCode(), 'x'.repeat(501), '198.51.100.61')).status).toBe(400);
    expect(computerName('  Chrome\n on\tMac  ')).toBe('Chrome on Mac');
    expect(computerName('é'.repeat(100))).toBe('é'.repeat(80));
    expect(computerName('\u0000 ')).toBe('Computer');
  });

  it('closed until the owner key is set', async () => {
    h.config.ownerKey = undefined;
    const res = await signIn('483920');
    expect(res.status).toBe(503);
    expect(res.body.error.code).toBe('owner_not_configured');
  });
});

describe('computer sessions', () => {
  it('last used is written at most every 10 minutes', async () => {
    const { token, id } = await session();
    const lastUsed = async () => (await h.database.pool.query('SELECT last_used_at FROM computer_sessions WHERE id = $1', [id])).rows[0].last_used_at;
    h.advance(5);
    await h.call('GET', '/api/owner/me', as(token));
    expect(await lastUsed()).toEqual(new Date('2026-11-02T18:00:00Z'));
    h.advance(5);
    await h.call('GET', '/api/owner/me', as(token));
    expect(await lastUsed()).toEqual(new Date('2026-11-02T18:10:00Z'));
    h.advance(9);
    await h.call('GET', '/api/owner/me', as(token));
    expect(await lastUsed()).toEqual(new Date('2026-11-02T18:10:00Z'));
  });

  it('expire after 30 days', async () => {
    const { token } = await session();
    h.advance(30 * 24 * 60 - 1);
    expect((await h.call('GET', '/api/owner/me', as(token))).status).toBe(200);
    h.advance(1);
    const res = await h.call('GET', '/api/owner/me', as(token));
    expect(res.status).toBe(401);
    expect(res.body.error).toEqual({ code: 'unauthorized', message: "That owner key isn't right. Check it and sign in again." });
  });

  it('GET lists the computers signed in, newest used first, and which one is asking', async () => {
    const mac = await session('Chrome on Mac', '198.51.100.1');
    h.advance(20);
    const pc = await session('Edge on Windows', '198.51.100.2');
    h.advance(5);
    const gone = await session('Old laptop', '198.51.100.3');
    await h.call('DELETE', '/api/owner/computer-sessions/current', as(gone.token));
    h.advance(10);
    const fromMac = await h.call('GET', '/api/owner/computer-sessions', as(mac.token));
    expect(fromMac.status).toBe(200);
    expect(RESPONSES['computer-sessions'].safeParse(fromMac.body).success).toBe(true);
    expect(fromMac.body.sessions.map((s: { name: string; current: boolean }) => [s.name, s.current])).toEqual([
      ['Chrome on Mac', true],
      ['Edge on Windows', false],
    ]);
    const fromKey = await h.call('GET', '/api/owner/computer-sessions', owner);
    expect(fromKey.body.sessions.map((s: { id: string; current: boolean }) => [s.id, s.current])).toEqual([
      [mac.id, false],
      [pc.id, false],
    ]);
  });

  it('DELETE …/:id signs one computer out', async () => {
    const mac = await session('Chrome on Mac', '198.51.100.1');
    const pc = await session('Edge on Windows', '198.51.100.2');
    const res = await h.call('DELETE', `/api/owner/computer-sessions/${pc.id}`, as(mac.token));
    expect(res.status).toBe(204);
    expect((await h.call('GET', '/api/owner/me', as(pc.token))).status).toBe(401);
    expect((await h.call('GET', '/api/owner/me', as(mac.token))).status).toBe(200);
    // Again: still signed out. Unknown ids: 404.
    expect((await h.call('DELETE', `/api/owner/computer-sessions/${pc.id}`, owner)).status).toBe(204);
    expect((await h.call('DELETE', '/api/owner/computer-sessions/00000000-0000-4000-8000-0000000000ff', owner)).status).toBe(404);
    expect((await h.call('DELETE', '/api/owner/computer-sessions/nope', owner)).status).toBe(404);
  });

  it('DELETE … signs every computer out; the owner key keeps working', async () => {
    const mac = await session('Chrome on Mac', '198.51.100.1');
    const pc = await session('Edge on Windows', '198.51.100.2');
    expect((await h.call('DELETE', '/api/owner/computer-sessions', as(mac.token))).status).toBe(204);
    for (const s of [mac, pc]) expect((await h.call('GET', '/api/owner/me', as(s.token))).status).toBe(401);
    expect((await h.call('GET', '/api/owner/me', owner)).status).toBe(200);
    expect((await h.call('GET', '/api/owner/computer-sessions', owner)).body.sessions).toEqual([]);
  });

  it('DELETE …/current is the website’s Sign out: a computer signs itself out (the owner key has nothing to sign out)', async () => {
    const mac = await session();
    const res = await h.call('DELETE', '/api/owner/computer-sessions/current', as(mac.token));
    expect(res.status).toBe(204);
    expect((await h.call('GET', '/api/owner/me', as(mac.token))).status).toBe(401);
    expect((await h.call('DELETE', '/api/owner/computer-sessions/current', as(mac.token))).status).toBe(401);
    const withKey = await h.call('DELETE', '/api/owner/computer-sessions/current', owner);
    expect(withKey.status).toBe(400);
    expect(withKey.body.error.message).toBe('Only a computer that is signed in can sign itself out.');
  });

  it('ended sessions are cleared out when a computer signs in', async () => {
    const old = await session('Old laptop', '198.51.100.1');
    await h.call('DELETE', '/api/owner/computer-sessions/current', as(old.token));
    const stale = await session('Stale', '198.51.100.2');
    h.advance(31 * 24 * 60);
    await session('Chrome on Mac', '198.51.100.3');
    const { rows } = await h.database.pool.query('SELECT name FROM computer_sessions');
    expect(rows).toEqual([{ name: 'Chrome on Mac' }]);
    expect(stale.id).toBeDefined();
  });

  it('a session token is never mistaken for the owner key, nor the owner key for a session', async () => {
    const mac = await session();
    expect(mac.token).not.toBe(OWNER_KEY);
    const tampered = `${mac.token.slice(0, -1)}${mac.token.endsWith('A') ? 'B' : 'A'}`;
    expect((await h.call('GET', '/api/owner/me', as(tampered))).status).toBe(401);
    expect((await h.call('GET', '/api/owner/me', { headers: { authorization: mac.token } })).status).toBe(401);
  });
});

describe('a new owner key signs every computer out', () => {
  it('session tokens are sealed with the owner key: after OWNER_KEY changes, they stop working', async () => {
    const mac = await session();
    expect((await h.call('GET', '/api/owner/me', as(mac.token))).status).toBe(200);
    h.config.ownerKey = `${OWNER_KEY}-rotated`;
    const res = await h.call('GET', '/api/owner/me', as(mac.token));
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('unauthorized');
    // A code made with the old key doesn't work with the new one either.
    h.config.ownerKey = OWNER_KEY;
    const code = await newCode();
    const rotated = `${OWNER_KEY}-rotated`;
    h.config.ownerKey = rotated;
    expect((await signIn(code, 'Chrome on Mac', '198.51.100.70')).body.error).toEqual(wrongCode);
    // With the new key, a new code signs in.
    const minted = await h.call('POST', '/api/owner/computer-codes', { headers: { authorization: `Bearer ${rotated}` } });
    expect(minted.status, minted.text).toBe(201);
    const fresh = await signIn(minted.body.code, 'Chrome on Mac', '198.51.100.71');
    expect(fresh.status).toBe(201);
    expect((await h.call('GET', '/api/owner/me', as(fresh.body.token))).status).toBe(200);
  });

  it('a token that isn’t sealed with the key is turned down without looking in the database', async () => {
    const forged = Buffer.alloc(32, 3).toString('base64url');
    const { rows } = await h.database.pool.query('SELECT count(*)::int AS n FROM computer_sessions');
    expect(rows[0].n).toBe(0);
    await h.database.pool.query(
      `INSERT INTO computer_sessions (id, token_hash, name, created_at, last_used_at, expires_at)
       VALUES (gen_random_uuid(), $1, 'Forged', now(), now(), now() + interval '1 day')`,
      [sha256(forged)],
    );
    expect((await h.call('GET', '/api/owner/me', as(forged))).status).toBe(401);
  });
});
