import type { Review, Reviews, ReviewSource } from '../api/types';
import { Icon } from '../components/Icon';
import { ErrorState, Loading, PreferToCall, Stars } from '../components/ui';
import { usePageMeta } from '../components/usePageMeta';
import { useCatalog } from '../data/catalog';
import { FALLBACK_SHOP } from '../data/fallback';
import { useReviews } from '../data/reviews';
import { DemoNotice } from '../demo/DemoNotice';
import { isDemo } from '../demo/mode';
import { MONTH_SHORT, localDate, parseDate } from '../lib/shopTime';

// Live reviews from Google and Yelp, each in its own section with its own
// attribution, never mixed or averaged together (Google's and Yelp's terms).
//
// The demo has no reviews from Google or Yelp, only samples that say so: they're
// shown as "Sample reviews", with none of Google's labels, attribution or terms,
// and links to the shop's real reviews.

const GOOGLE_TERMS = 'https://maps.google.com/help/terms_maps/';
const GOOGLE_PRIVACY = 'https://policies.google.com/privacy';

export function ReviewsPage() {
  usePageMeta('Reviews', 'What clients say about Izzy Clipz Barbershop in Oceanside, live from Google and Yelp.');
  const reviews = useReviews();
  const catalog = useCatalog();
  const googleMaps = catalog?.shop.googleMapsUrl ?? FALLBACK_SHOP.googleMapsUrl;
  const reviewUrl = catalog?.shop.googleReviewUrl;
  const zone = catalog?.timeZone ?? 'America/Los_Angeles';
  const demo = isDemo();

  return (
    <>
      <header className="page-header container">
        <h1>Reviews</h1>
        <p className="lead secondary">
          {demo
            ? 'On the real site, this page shows what clients say about Izzy Clipz on Google and Yelp.'
            : 'What clients say about Izzy Clipz on Google and Yelp, as they wrote it.'}
        </p>
        <PreferToCall className="page-header__call" />
      </header>
      <div className="container container--narrow reviews">
        <DemoNotice about="reviews" />
        {reviews.status === 'loading' ? <Loading text={demo ? 'Loading the sample reviews…' : 'Loading reviews from Google…'} /> : null}
        {reviews.status === 'error' ? (
          <div className="reviews__error">
            <ErrorState title="Couldn't load the reviews" message={reviews.message} onRetry={reviews.retry} />
            <div className="actions actions--center">
              <a className="button button--secondary" href={googleMaps}>
                See our reviews on Google Maps
              </a>
              <a className="button button--secondary" href={FALLBACK_SHOP.yelpUrl}>
                Read our reviews on Yelp
              </a>
            </div>
          </div>
        ) : null}
        {reviews.status === 'ready' && demo ? <SampleSection reviews={reviews.reviews} zone={zone} /> : null}
        {reviews.status === 'ready' && !demo ? (
          <>
            {reviews.reviews.google.available ? <GoogleSection source={reviews.reviews.google} zone={zone} /> : null}
            {reviews.reviews.yelp.available ? <YelpSection source={reviews.reviews.yelp} zone={zone} /> : null}
            {!reviews.reviews.google.available || !reviews.reviews.yelp.available ? (
              <section className="review-source" aria-labelledby="reviews-elsewhere" data-testid="reviews-elsewhere">
                <h2 id="reviews-elsewhere" className="review-source__title">
                  {!reviews.reviews.google.available && !reviews.reviews.yelp.available
                    ? "Reviews can't be shown here right now"
                    : 'More reviews'}
                </h2>
                <p>
                  {!reviews.reviews.google.available && !reviews.reviews.yelp.available
                    ? 'Read them on Google Maps or Yelp instead, where clients wrote them.'
                    : 'Read more of what clients wrote, on the site itself.'}
                </p>
                <div className="review-source__links">
                  {!reviews.reviews.google.available ? (
                    <a className="button button--secondary" href={reviews.reviews.google.url}>
                      See our reviews on Google Maps <Icon name="external" className="button__icon" />
                    </a>
                  ) : null}
                  {!reviews.reviews.yelp.available ? (
                    <a className="button button--secondary" href={reviews.reviews.yelp.url}>
                      Read our reviews on Yelp <Icon name="external" className="button__icon" />
                    </a>
                  ) : null}
                </div>
              </section>
            ) : null}
          </>
        ) : null}
      </div>

      <section className="band band--gray" aria-labelledby="your-turn">
        <div className="container container--narrow your-turn">
          <h2 id="your-turn">Your turn.</h2>
          <p className="lead secondary">Had a good cut? A few words on Google mean a lot to the team.</p>
          {reviewUrl ? (
            <a className="button button--primary button--large" href={reviewUrl}>
              Leave a review on Google
            </a>
          ) : null}
        </div>
      </section>

      {reviews.status === 'ready' && reviews.reviews.google.available && !demo ? (
        <div className="container container--narrow reviews__terms">
          <p className="secondary small">
            This site shows content from Google Maps. Using it is subject to Google's terms and privacy policy:{' '}
            <a href={GOOGLE_TERMS}>Google Maps terms</a> and <a href={GOOGLE_PRIVACY}>Google privacy policy</a>.
          </p>
        </div>
      ) : null}
    </>
  );
}

function GoogleSection({ source, zone }: { source: ReviewSource; zone: string }) {
  return (
    <section className="review-source" aria-labelledby="google-reviews" data-testid="google-reviews">
      {/* Google's attribution, as its rules ask: plain text, regular weight, not restyled. */}
      <h2 id="google-reviews" className="review-source__attribution">
        Reviews from Google Maps
      </h2>
      {source.rating != null ? <Score rating={source.rating} count={source.count} site="Google" /> : null}
      {source.reviews.length > 0 ? (
        <>
          <div>
            <h3 className="review-source__subtitle">Most relevant on Google</h3>
            <p className="secondary">Up to five reviews that Google picks, in Google's order.</p>
          </div>
          <ol className="review-list">
            {source.reviews.map((review, index) => (
              <ReviewItem key={`${review.author}-${index}`} review={review} site="Google Maps" linkTitle="View on Google Maps" zone={zone} />
            ))}
          </ol>
        </>
      ) : null}
      <a className="button button--secondary" href={source.url}>
        See all reviews on Google Maps <Icon name="external" className="button__icon" />
      </a>
      <p className="secondary small">Reviews aren't verified by Google, but Google checks for and removes fake content when it's identified.</p>
    </section>
  );
}

/** The demo's samples: not Google's or Yelp's, so under a heading of their own, with links to the real ones. */
function SampleSection({ reviews, zone }: { reviews: Reviews; zone: string }) {
  const samples = [...reviews.google.reviews, ...reviews.yelp.reviews];
  return (
    <section className="review-source" aria-labelledby="sample-reviews" data-testid="sample-reviews">
      <h2 id="sample-reviews" className="review-source__title">
        Sample reviews
      </h2>
      {samples.length > 0 ? (
        <ol className="review-list">
          {samples.map((review, index) => (
            <ReviewItem key={`${review.author}-${index}`} review={review} zone={zone} />
          ))}
        </ol>
      ) : null}
      <div className="review-source__links">
        <a className="button button--secondary" href={reviews.google.url}>
          See our reviews on Google Maps <Icon name="external" className="button__icon" />
        </a>
        <a className="button button--secondary" href={reviews.yelp.url}>
          Read our reviews on Yelp <Icon name="external" className="button__icon" />
        </a>
      </div>
    </section>
  );
}

function YelpSection({ source, zone }: { source: ReviewSource; zone: string }) {
  return (
    <section className="review-source" aria-labelledby="yelp-reviews" data-testid="yelp-reviews">
      <h2 id="yelp-reviews" className="review-source__title">
        Reviews from Yelp
      </h2>
      {source.rating != null ? <Score rating={source.rating} count={source.count} site="Yelp" /> : null}
      {source.reviews.length > 0 ? (
        <ol className="review-list">
          {source.reviews.map((review, index) => (
            <ReviewItem key={`${review.author}-${index}`} review={review} site="Yelp" linkTitle="Read more on Yelp" zone={zone} />
          ))}
        </ol>
      ) : null}
      <a className="button button--secondary" href={source.url}>
        Read our reviews on Yelp <Icon name="external" className="button__icon" />
      </a>
    </section>
  );
}

function Score({ rating, count, site }: { rating: number; count: number | null; site: string }) {
  return (
    <div className="score">
      <span className="score__number">{rating.toFixed(1)}</span>
      <span className="score__detail">
        <Stars rating={rating} size={20} />
        <span className="secondary">{count != null ? `${count === 1 ? '1 review' : `${count} reviews`} on ${site}` : `On ${site}`}</span>
      </span>
    </div>
  );
}

/** "Oct 17, 2026" on the shop's calendar. */
function publishedLabel(review: Review, zone: string): string | null {
  if (review.relativeTime) return review.relativeTime;
  if (!review.publishedAt) return null;
  const { year, month, day } = parseDate(localDate(new Date(review.publishedAt), zone));
  return `${MONTH_SHORT[month - 1]} ${day}, ${year}`;
}

/** One review; `site` and `linkTitle` name where its link goes ("Google Maps", "View on Google Maps"). Samples have neither. */
function ReviewItem({ review, site, linkTitle, zone }: { review: Review; site?: string; linkTitle?: string; zone: string }) {
  const when = publishedLabel(review, zone);
  return (
    <li className="review">
      <div className="review__header">
        {review.authorPhotoUrl ? (
          <img className="review__photo" src={review.authorPhotoUrl} alt="" width={44} height={44} loading="lazy" referrerPolicy="no-referrer" />
        ) : (
          <span className="review__photo review__photo--initial" aria-hidden="true">
            {review.author.slice(0, 1).toUpperCase()}
          </span>
        )}
        <div className="review__who">
          {review.authorUrl ? (
            <a className="review__author inline-link" href={review.authorUrl}>
              {review.author}
            </a>
          ) : (
            <span className="review__author">{review.author}</span>
          )}
          <span className="review__meta">
            <Stars rating={review.rating} size={15} />
            {when ? <span className="secondary">{when}</span> : null}
          </span>
        </div>
      </div>
      {review.text ? <p className="review__text">{review.text}</p> : null}
      {review.url && site && linkTitle ? (
        <a className="review__link" href={review.url} aria-label={`${linkTitle}: ${review.author}'s review on ${site}`}>
          {linkTitle} <Icon name="external" className="inline-icon" />
        </a>
      ) : null}
    </li>
  );
}
