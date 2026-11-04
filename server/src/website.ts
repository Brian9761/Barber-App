import { readFileSync } from 'node:fs';
import { z } from 'zod';
import { catalogSchema } from './catalog.js';
import { json } from './http.js';

// GET /api/catalog: the website's menu, team, hours and booking rules, exactly
// what this server books against (data/catalog.json, exported from
// IzzyClipzKit), with what the Kit exports for the website only: the shop's own
// details (`shop`), each service's description, category and whether it's a
// favorite, and each barber's title, bio and tile letters. The booking code
// reads the same file through catalog.ts, which ignores those fields.
//
// Public and the same for every visitor, so browsers and Vercel's CDN may keep
// it for 5 minutes. It needs no database.

const text = z.string().min(1);
const webUrl = z.string().regex(/^https:\/\/[^\s]+$/);
const instagram = z.object({ handle: z.string().regex(/^[A-Za-z0-9._]{1,30}$/), url: webUrl });

const shopSchema = z.object({
  name: text,
  fullName: text,
  tagline: text,
  phone: z.object({ e164: z.string().regex(/^\+1\d{10}$/), display: text }),
  address: z.object({
    street: text,
    unit: text.optional(),
    city: text,
    state: text,
    postalCode: text,
    lines: z.array(text).min(1),
  }),
  coordinate: z.object({ latitude: z.number().min(-90).max(90), longitude: z.number().min(-180).max(180) }),
  instagram,
  appleMapsUrl: webUrl,
  appleMapsDirectionsUrl: webUrl,
  googleMapsUrl: webUrl,
  googleMapsDirectionsUrl: webUrl,
  googleReviewUrl: webUrl,
  websiteUrl: webUrl,
  about: z.array(text),
  highlights: z.array(text),
  paymentMethods: z.array(text),
  accessibility: z.array(text),
});

/** catalog.json as the website gets it: the booking catalog plus the shop and the menu's and team's words. */
export const websiteCatalogSchema = catalogSchema.extend({
  services: z.array(
    z.object({ id: text, name: text, description: text.optional(), category: text, popular: z.boolean() }),
  ),
  barbers: z.array(
    z.object({
      id: z.string().regex(/^[a-z0-9-]+$/),
      name: text,
      title: text,
      bio: text,
      specialties: z.array(text),
      monogram: text,
      instagram: instagram.optional(),
    }),
  ),
  shop: shopSchema,
});

export type WebsiteCatalog = z.output<typeof websiteCatalogSchema>;

let shared: WebsiteCatalog | undefined;

/** The bundled data/catalog.json with the website's fields, checked once. Throws if they're missing. */
export function loadWebsiteCatalog(): WebsiteCatalog {
  shared ??= websiteCatalogSchema.parse(JSON.parse(readFileSync(new URL('../data/catalog.json', import.meta.url), 'utf8')));
  return shared;
}

export async function getCatalog(): Promise<Response> {
  return json(loadWebsiteCatalog(), 200, { 'cache-control': 'public, max-age=300' });
}
