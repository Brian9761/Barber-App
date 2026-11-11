import type { Reviews, Shop } from '../api/types';
import { FALLBACK_SHOP } from '../data/fallback';

/**
 * The demo's reviews: SAMPLES, not the shop's rating and not anyone's real words (the real site
 * shows the shop's reviews live from Google, and only links to Yelp). They're named "Sample
 * reviewer" and say what they are, and there's no rating or count, so the demo never shows a
 * made-up score as Google's. Yelp isn't set up: the site never shows Yelp's reviews.
 */
export function sampleReviews(shop: Shop, now: Date): Reviews {
  return {
    google: {
      available: true,
      rating: null,
      count: null,
      url: shop.googleMapsUrl,
      reviews: [
        {
          author: 'Sample reviewer A',
          authorPhotoUrl: null,
          authorUrl: null,
          rating: 5,
          text: "A sample review for the demo version. The shop's real reviews come from Google.",
          relativeTime: 'a week ago',
          publishedAt: null,
          url: null,
        },
        {
          author: 'Sample reviewer B',
          authorPhotoUrl: null,
          authorUrl: null,
          rating: 4,
          text: 'Another sample review, to show how reviews look on this page.',
          relativeTime: 'a month ago',
          publishedAt: null,
          url: null,
        },
      ],
      fetchedAt: now.toISOString().replace(/\.\d{3}Z$/, 'Z'),
    },
    yelp: { available: false, rating: null, count: null, url: FALLBACK_SHOP.yelpUrl, reviews: [], fetchedAt: null },
  };
}
