import { describe, expect, it } from 'vitest';
import { catalog, reviews, reviewsUnavailable } from '../test/api';
import { FALLBACK_SHOP } from './fallback';

describe('the shop details shown before the catalog arrives', () => {
  it('match the catalog the server sends', () => {
    expect(FALLBACK_SHOP.name).toBe(catalog.shop.name);
    expect(FALLBACK_SHOP.fullName).toBe(catalog.shop.fullName);
    expect(FALLBACK_SHOP.phone).toEqual(catalog.shop.phone);
    expect(FALLBACK_SHOP.addressLines).toEqual(catalog.shop.address.lines);
    expect(FALLBACK_SHOP.instagram).toEqual(catalog.shop.instagram);
    expect(FALLBACK_SHOP.googleMapsUrl).toBe(catalog.shop.googleMapsUrl);
  });

  it('link to the same Yelp page the server reads reviews from', () => {
    // The server's link carries Yelp's tracking parameters; the page is the same.
    const fromServer = new URL(reviews.yelp.url);
    expect(FALLBACK_SHOP.yelpUrl).toBe(`${fromServer.origin}${fromServer.pathname}`);
    expect(FALLBACK_SHOP.yelpUrl).toBe(reviewsUnavailable.yelp.url);
  });
});
