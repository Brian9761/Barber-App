import { z } from 'zod';
import { requireOwner } from './auth.js';
import { ApiError, json, mediaType, noContent, readBytes, readJsonObject } from './http.js';
import type { Context } from './router.js';
import { productJSON, type ProductRow } from './serialize.js';
import { charLength, parse, UUID_RE } from './validation.js';

export const MAX_PHOTO_BYTES = 4 * 1024 * 1024;

const COLUMNS = 'id, name, description, price_cents, image_url, visible, sort';
const notFound = () => new ApiError('not_found', "We couldn't find that product. It may have been deleted.");

// GET /api/products → visible products, in the owner's order.

export async function listPublicProducts({ deps }: Context): Promise<Response> {
  const { rows } = await deps.db.query<ProductRow>(
    `SELECT ${COLUMNS} FROM products WHERE visible ORDER BY sort, created_at, id`,
  );
  return json({ products: rows.map(productJSON) });
}

// Owner product endpoints.

export async function listOwnerProducts(ctx: Context): Promise<Response> {
  requireOwner(ctx.request, ctx.deps.config);
  const { rows } = await ctx.deps.db.query<ProductRow>(`SELECT ${COLUMNS} FROM products ORDER BY sort, created_at, id`);
  return json({ products: rows.map(productJSON) });
}

const name = z
  .string({ error: 'Give the product a name.' })
  .trim()
  .refine((v) => v.length > 0, { error: 'Give the product a name.' })
  .refine((v) => charLength(v) <= 80, { error: 'Keep the name to 80 characters or fewer.' })
  .refine((v) => !/[\u0000-\u001f\u007f]/.test(v), { error: 'The name has characters we can’t use.' });

const description = z
  .string({ error: 'The description must be text.' })
  .nullish()
  .transform((v) => {
    const t = v?.trim() ?? '';
    return t === '' ? null : t;
  })
  .refine((v) => v === null || charLength(v) <= 500, { error: 'Keep the description to 500 characters or fewer.' });

const priceCents = z
  .number({ error: 'The price must be a whole number of cents.' })
  .int({ error: 'The price must be a whole number of cents.' })
  .min(0, { error: "The price can't be negative." })
  .max(1_000_000, { error: 'That price is too high.' })
  .nullish();

const visible = z.boolean({ error: 'visible must be true or false.' });

const createBody = z.object({ name, description: description.optional(), priceCents, visible: visible.optional() });

export async function createProduct(ctx: Context): Promise<Response> {
  requireOwner(ctx.request, ctx.deps.config);
  const body = parse(createBody, await readJsonObject(ctx.request));
  const now = ctx.deps.now();
  const { rows } = await ctx.deps.db.query<ProductRow>(
    `INSERT INTO products (id, name, description, price_cents, image_url, visible, sort, created_at, updated_at)
     VALUES ($1, $2, $3, $4, NULL, $5, (SELECT COALESCE(max(sort), 0) + 1 FROM products), $6, $6)
     RETURNING ${COLUMNS}`,
    [ctx.deps.uuid(), body.name, body.description ?? null, body.priceCents ?? null, body.visible ?? true, now],
  );
  const row = rows[0];
  if (!row) throw new Error('Insert returned no row');
  return json({ product: productJSON(row) }, 201);
}

const patchBody = z.object({
  name: name.optional(),
  description: description.optional(),
  priceCents: priceCents.optional(),
  visible: visible.optional(),
});

export async function updateProduct(ctx: Context): Promise<Response> {
  requireOwner(ctx.request, ctx.deps.config);
  const id = productId(ctx);
  const raw = await readJsonObject(ctx.request);
  const body = parse(patchBody, raw);
  // Only fields that were sent change; `null` clears description or price.
  const sets: string[] = [];
  const values: unknown[] = [id];
  const set = (column: string, value: unknown) => {
    values.push(value);
    sets.push(`${column} = $${values.length}`);
  };
  if ('name' in raw && body.name !== undefined) set('name', body.name);
  if ('description' in raw) set('description', body.description ?? null);
  if ('priceCents' in raw) set('price_cents', body.priceCents ?? null);
  if ('visible' in raw && body.visible !== undefined) set('visible', body.visible);
  if (sets.length === 0) throw new ApiError('invalid_request', 'Nothing to change. Send name, description, priceCents or visible.');
  set('updated_at', ctx.deps.now());
  const { rows } = await ctx.deps.db.query<ProductRow>(
    `UPDATE products SET ${sets.join(', ')} WHERE id = $1 RETURNING ${COLUMNS}`,
    values,
  );
  const row = rows[0];
  if (!row) throw notFound();
  return json({ product: productJSON(row) });
}

export async function deleteProduct(ctx: Context): Promise<Response> {
  requireOwner(ctx.request, ctx.deps.config);
  const id = productId(ctx);
  const { rows } = await ctx.deps.db.query<{ image_url: string | null }>(
    'DELETE FROM products WHERE id = $1 RETURNING image_url',
    [id],
  );
  const row = rows[0];
  if (!row) throw notFound();
  if (row.image_url) await removeBlob(ctx, row.image_url);
  return noContent();
}

// POST /api/owner/products/:id/photo, body = JPEG bytes (≤ 4 MB).

export async function uploadProductPhoto(ctx: Context): Promise<Response> {
  requireOwner(ctx.request, ctx.deps.config);
  const id = productId(ctx);
  if (mediaType(ctx.request) !== 'image/jpeg') {
    throw new ApiError('invalid_request', 'Send the photo as a JPEG (Content-Type: image/jpeg).', { status: 415 });
  }
  const bytes = await readBytes(ctx.request, MAX_PHOTO_BYTES);
  if (bytes.byteLength < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes[2] !== 0xff) {
    throw new ApiError('invalid_request', "That file isn't a JPEG photo.");
  }
  const { rows: existing } = await ctx.deps.db.query<{ image_url: string | null }>(
    'SELECT image_url FROM products WHERE id = $1',
    [id],
  );
  if (!existing[0]) throw notFound();

  let url: string;
  try {
    ({ url } = await ctx.deps.blob.put(`products/${id}.jpg`, bytes, { contentType: 'image/jpeg' }));
  } catch (error) {
    ctx.deps.log.error('Photo upload to Blob failed', { error: error instanceof Error ? error.message : String(error) });
    throw new ApiError('server_error', "We couldn't save the photo. Please try again.");
  }

  const saved = await ctx.deps.db.transaction(async (tx) => {
    const { rows: old } = await tx.query<{ image_url: string | null }>(
      'SELECT image_url FROM products WHERE id = $1 FOR UPDATE',
      [id],
    );
    if (!old[0]) return null;
    const { rows } = await tx.query<ProductRow>(
      `UPDATE products SET image_url = $2, updated_at = $3 WHERE id = $1 RETURNING ${COLUMNS}`,
      [id, url, ctx.deps.now()],
    );
    return rows[0] ? { row: rows[0], oldUrl: old[0].image_url } : null;
  });
  if (!saved) {
    // Deleted while uploading: don't leave the new photo behind.
    await removeBlob(ctx, url);
    throw notFound();
  }
  if (saved.oldUrl && saved.oldUrl !== url) await removeBlob(ctx, saved.oldUrl);
  const row = saved.row;
  return json({ product: productJSON(row) });
}

function productId(ctx: Context): string {
  const id = ctx.params.id ?? '';
  if (!UUID_RE.test(id)) throw notFound();
  return id;
}

async function removeBlob(ctx: Context, url: string): Promise<void> {
  try {
    await ctx.deps.blob.del(url);
  } catch (error) {
    // A leftover photo costs a little storage; it's not worth failing the request.
    ctx.deps.log.warn('Could not delete an old product photo', { url, error: error instanceof Error ? error.message : String(error) });
  }
}
