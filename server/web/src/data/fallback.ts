// The few shop details every page shows even before the catalog arrives, or when
// it can't be reached: how to call and where to come. The catalog from
// GET /api/catalog is the source of truth; a unit test checks these against the
// server's catalog.json contract fixture.

export const FALLBACK_SHOP = {
  name: 'Izzy Clipz',
  fullName: 'Izzy Clipz Barbershop',
  phone: { e164: '+14423413053', display: '(442) 341-3053' },
  addressLines: ['1919 Mission Ave, Ste 105', 'Oceanside, CA 92058'],
  instagram: { handle: 'izzy_clipz_barbershop_', url: 'https://www.instagram.com/izzy_clipz_barbershop_/' },
  googleMapsUrl:
    'https://www.google.com/maps/search/?api=1&query=Izzy%20Clipz%20Barbershop&query_place_id=ChIJGz5HChRv3IARYJJy_6jyRm8',
  yelpUrl: 'https://www.yelp.com/biz/izzy-clipz-barbershop-oceanside',
} as const;
