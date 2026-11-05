import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import analyticsFixture from '../../../../test/fixtures/contract/analytics.json';
import codeFixture from '../../../../test/fixtures/contract/computer-code.json';
import sessionFixture from '../../../../test/fixtures/contract/computer-session-created.json';
import saleFixture from '../../../../test/fixtures/contract/sale-created.json';
import { isApiError } from '../../api/errors';
import { apiError, mockApi } from '../../test/api';
import { SESSION_KEY, session } from '../session';
import { httpOwnerApi, OWNER_OFFLINE_MESSAGE } from './http';

// The owner API over the network: this computer's session token on every call, the key
// only ever used to make a code, the Idempotency-Key on a sale, and a session the server
// no longer knows ending here too.

const TOKEN = sessionFixture.token;

beforeEach(() => {
  session.reset();
});

afterEach(() => session.reset());

function signIn() {
  session.signIn(sessionFixture as never);
}

describe('signing in', () => {
  it('trades the code for a session, naming this computer, with no token sent', async () => {
    const api = mockApi([['POST /api/computer-sessions', { status: 201, body: sessionFixture }]]);
    const signed = await httpOwnerApi.signIn('483920', 'Chrome on Mac');
    expect(signed.token).toBe(TOKEN);
    expect(api.calls[0]).toMatchObject({ body: { code: '483920', name: 'Chrome on Mac' } });
    expect(api.calls[0]!.headers.authorization).toBeUndefined();
  });

  it('with the owner key: the key makes a code, the code a session, and only the session is kept', async () => {
    const api = mockApi([
      ['POST /api/owner/computer-codes', { status: 201, body: codeFixture }],
      ['POST /api/computer-sessions', { status: 201, body: sessionFixture }],
    ]);
    const signed = await httpOwnerApi.signInWithKey('the-owner-key-for-this-test', 'Edge on Windows');
    expect(api.calls.map((c) => `${c.method} ${c.path}`)).toEqual(['POST /api/owner/computer-codes', 'POST /api/computer-sessions']);
    expect(api.calls[0]!.headers.authorization).toBe('Bearer the-owner-key-for-this-test');
    expect(api.calls[1]).toMatchObject({ body: { code: '483920', name: 'Edge on Windows' } });
    session.signIn(signed);
    expect(localStorage.getItem(SESSION_KEY)).not.toContain('the-owner-key-for-this-test');
    expect(JSON.parse(localStorage.getItem(SESSION_KEY)!)).toMatchObject({ token: TOKEN, name: 'Chrome on Mac' });
  });

  it('says what to do with a wrong code', async () => {
    mockApi([
      ['POST /api/computer-sessions', apiError('wrong_code', "That code isn't right or has run out. Open Izzy Clipz Business → Settings → Use on a computer for a new one.", 400)],
    ]);
    const error = await httpOwnerApi.signIn('000000', 'Chrome on Mac').catch((e: unknown) => e);
    expect(isApiError(error) && error.code).toBe('wrong_code');
  });
});

describe('the owner’s calls', () => {
  it('send this computer’s session token, and a sale its Idempotency-Key', async () => {
    signIn();
    const api = mockApi([
      ['GET /api/owner/analytics', { body: analyticsFixture }],
      ['POST /api/owner/sales', { status: 201, body: saleFixture }],
    ]);
    await httpOwnerApi.analytics({ from: '2026-11-01', to: '2026-11-07', barberId: 'flowxbori' });
    expect(api.calls[0]!.search).toBe('?from=2026-11-01&to=2026-11-07&barberId=flowxbori');
    expect(api.calls[0]!.headers.authorization).toBe(`Bearer ${TOKEN}`);
    const key = 'K'.repeat(43);
    const sale = await httpOwnerApi.createSale({ barberId: 'flowxbori', method: 'cash', items: [{ kind: 'custom', name: 'Tip', unitCents: 500 }] }, key);
    expect(sale.totalCents).toBe(9600);
    expect(api.calls[1]!.headers['idempotency-key']).toBe(key);
    expect(api.calls[1]!.headers['content-type']).toBe('application/json');
  });

  it('end the session here when the server no longer knows it (signed out from the iPhone)', async () => {
    signIn();
    mockApi([['GET /api/owner/appointments', apiError('unauthorized', "That owner key isn't right. Check it and sign in again.", 401)]]);
    await expect(httpOwnerApi.appointments('2026-11-04')).rejects.toMatchObject({ status: 401 });
    expect(session.current()).toMatchObject({ session: null, reason: 'expired' });
    expect(localStorage.getItem(SESSION_KEY)).toBeNull();
  });

  it('say so plainly when the server can’t be reached', async () => {
    signIn();
    mockApi([['GET /api/owner/products', 'offline']]);
    await expect(httpOwnerApi.products()).rejects.toMatchObject({ code: 'offline', message: OWNER_OFFLINE_MESSAGE });
    // Still signed in: being offline isn't being signed out.
    expect(session.current().session).not.toBeNull();
  });

  it('sign this computer out with DELETE …/current, which answers nothing', async () => {
    signIn();
    const api = mockApi([['DELETE /api/owner/computer-sessions/current', { status: 204 }]]);
    // jsdom's Response can't be a 204 with a body; the mock answers {} with a 204 status.
    await httpOwnerApi.signOut().catch(() => undefined);
    expect(api.calls[0]).toMatchObject({ method: 'DELETE', path: '/api/owner/computer-sessions/current' });
  });

  it('never go out without a session', async () => {
    mockApi([]);
    await expect(httpOwnerApi.products()).rejects.toMatchObject({ code: 'signed_out' });
  });

  it('send a product photo as a JPEG', async () => {
    signIn();
    const api = mockApi([['POST /api/owner/products/*', { body: { product: { id: 'p', name: 'Pomade', description: null, priceCents: 1800, imageUrl: 'https://x/p.jpg', visible: true } } }]]);
    await httpOwnerApi.uploadProductPhoto('00000000-0000-4000-8000-000000000001', new Blob([new Uint8Array([0xff, 0xd8, 0xff])], { type: 'image/jpeg' }));
    expect(api.calls[0]!.headers['content-type']).toBe('image/jpeg');
    expect(api.calls[0]!.path).toBe('/api/owner/products/00000000-0000-4000-8000-000000000001/photo');
  });
});
