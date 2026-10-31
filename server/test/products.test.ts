import { describe, expect, it } from 'vitest';
import { useHarness, type RequestBody } from './helpers/harness.js';

// Monday Nov 2 2026, 11:10 AM PST.
const h = useHarness({ now: '2026-11-02T19:10:00Z' });

const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0xff, 0xd9]);

describe('owner products', () => {
  const create = (body: unknown) => h.call('POST', '/api/owner/products', { owner: true, body });

  it('creates, lists (owner: all; public: visible only, in order), edits and deletes', async () => {
    const pomade = await create({ name: '  Matte pomade ', description: 'Medium hold', priceCents: 1800 });
    expect(pomade.status).toBe(201);
    expect(pomade.body.product).toEqual({
      id: expect.any(String),
      name: 'Matte pomade',
      description: 'Medium hold',
      priceCents: 1800,
      imageUrl: null,
      visible: true,
    });
    const hidden = await create({ name: 'Beard oil', visible: false });
    expect(hidden.body.product).toMatchObject({ description: null, priceCents: null, visible: false });
    const comb = await create({ name: 'Comb', priceCents: 0 });

    const pub = await h.call('GET', '/api/products');
    expect(pub.status).toBe(200);
    expect(pub.body.products.map((p: { name: string }) => p.name)).toEqual(['Matte pomade', 'Comb']);
    const all = await h.call('GET', '/api/owner/products', { owner: true });
    expect(all.body.products.map((p: { name: string }) => p.name)).toEqual(['Matte pomade', 'Beard oil', 'Comb']);

    const id = pomade.body.product.id;
    const renamed = await h.call('PATCH', `/api/owner/products/${id}`, { owner: true, body: { name: 'Clay pomade' } });
    expect(renamed.body.product).toMatchObject({ name: 'Clay pomade', description: 'Medium hold', priceCents: 1800 });
    const cleared = await h.call('PATCH', `/api/owner/products/${id}`, { owner: true, body: { description: null, priceCents: null, visible: false } });
    expect(cleared.body.product).toMatchObject({ name: 'Clay pomade', description: null, priceCents: null, visible: false });
    expect((await h.call('GET', '/api/products')).body.products.map((p: { id: string }) => p.id)).toEqual([comb.body.product.id]);

    expect((await h.call('DELETE', `/api/owner/products/${id}`, { owner: true })).status).toBe(204);
    expect((await h.call('DELETE', `/api/owner/products/${id}`, { owner: true })).status).toBe(404);
    expect((await h.call('PATCH', `/api/owner/products/${id}`, { owner: true, body: { name: 'x' } })).status).toBe(404);
  });

  it('validates product fields', async () => {
    for (const body of [{}, { name: '' }, { name: 'n'.repeat(81) }, { name: 'A', priceCents: -1 }, { name: 'A', priceCents: 12.5 }, { name: 'A', priceCents: '12' }, { name: 'A', visible: 'yes' }, { name: 'A', description: 'd'.repeat(501) }]) {
      const res = await create(body);
      expect(res.status, JSON.stringify(body)).toBe(400);
    }
    const p = await create({ name: 'Ok' });
    const empty = await h.call('PATCH', `/api/owner/products/${p.body.product.id}`, { owner: true, body: {} });
    expect(empty.status).toBe(400);
    expect((await h.call('PATCH', `/api/owner/products/${p.body.product.id}`, { owner: true, body: { name: '' } })).status).toBe(400);
  });

  it('uploads a JPEG to Blob, replaces the old photo, and deletes it with the product', async () => {
    const p = (await create({ name: 'Pomade' })).body.product;
    const upload = (bytes: RequestBody, type = 'image/jpeg') =>
      h.call('POST', `/api/owner/products/${p.id}/photo`, { owner: true, rawBody: bytes, headers: { 'content-type': type } });
    const first = await upload(JPEG);
    expect(first.status).toBe(200);
    expect(first.body.product.imageUrl).toBe(`https://fixture.public.blob.vercel-storage.com/products/${p.id}-r1.jpg`);
    expect(h.blob.puts[0]).toMatchObject({ pathname: `products/${p.id}.jpg`, contentType: 'image/jpeg', bytes: JPEG.byteLength });

    const second = await upload(JPEG);
    expect(second.body.product.imageUrl).toMatch(/-r2\.jpg$/);
    expect(h.blob.deleted).toEqual([first.body.product.imageUrl]);
    expect((await h.call('GET', '/api/products')).body.products[0].imageUrl).toBe(second.body.product.imageUrl);

    await h.call('DELETE', `/api/owner/products/${p.id}`, { owner: true });
    expect(h.blob.deleted).toEqual([first.body.product.imageUrl, second.body.product.imageUrl]);
  });

  it('rejects photos that are not JPEG, too large, or for unknown products', async () => {
    const p = (await create({ name: 'Pomade' })).body.product;
    const url = `/api/owner/products/${p.id}/photo`;
    const png = await h.call('POST', url, { owner: true, rawBody: JPEG, headers: { 'content-type': 'image/png' } });
    expect(png.status).toBe(415);
    expect(png.body.error.code).toBe('invalid_request');
    const fake = await h.call('POST', url, { owner: true, rawBody: new Uint8Array([0x89, 0x50, 0x4e, 0x47, 1, 2]), headers: { 'content-type': 'image/jpeg' } });
    expect(fake.status).toBe(400);
    const big = new Uint8Array(4 * 1024 * 1024 + 1);
    big.set([0xff, 0xd8, 0xff]);
    const tooBig = await h.call('POST', url, { owner: true, rawBody: big, headers: { 'content-type': 'image/jpeg' } });
    expect(tooBig.status).toBe(413);
    const exactly = new Uint8Array(4 * 1024 * 1024);
    exactly.set([0xff, 0xd8, 0xff]);
    expect((await h.call('POST', url, { owner: true, rawBody: exactly, headers: { 'content-type': 'image/jpeg' } })).status).toBe(200);
    const unknown = await h.call('POST', '/api/owner/products/00000000-0000-4000-8000-0000000000ee/photo', {
      owner: true,
      rawBody: JPEG,
      headers: { 'content-type': 'image/jpeg' },
    });
    expect(unknown.status).toBe(404);
    expect(h.blob.puts).toHaveLength(1);
  });

  it('reports a Blob failure plainly and keeps the old photo; a failed delete is only logged', async () => {
    const p = (await create({ name: 'Pomade' })).body.product;
    const url = `/api/owner/products/${p.id}/photo`;
    const ok = await h.call('POST', url, { owner: true, rawBody: JPEG, headers: { 'content-type': 'image/jpeg' } });
    h.blob.failPut = true;
    const failed = await h.call('POST', url, { owner: true, rawBody: JPEG, headers: { 'content-type': 'image/jpeg' } });
    expect(failed.status).toBe(500);
    expect(failed.body.error).toEqual({ code: 'server_error', message: "We couldn't save the photo. Please try again." });
    expect((await h.call('GET', '/api/owner/products', { owner: true })).body.products[0].imageUrl).toBe(ok.body.product.imageUrl);
    h.blob.failPut = false;
    h.blob.failDel = true;
    expect((await h.call('DELETE', `/api/owner/products/${p.id}`, { owner: true })).status).toBe(204);
    expect(h.logs.some((l) => l.level === 'warn' && l.message.includes('old product photo'))).toBe(true);
  });
});
