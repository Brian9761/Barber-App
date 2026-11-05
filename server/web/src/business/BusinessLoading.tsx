import { Loading } from '../components/ui';

/**
 * While Izzy Clipz Business's own code loads (the first time it's opened): its black bar and
 * a calm "Loading", so nothing jumps when it arrives. Kept apart from the rest of Business,
 * so the site's pages carry only this.
 */
export function BusinessLoading() {
  return (
    <>
      <div className="biz-globalbar biz-globalbar--loading" aria-hidden="true" />
      <main id="main" tabIndex={-1} className="biz-main">
        <div className="container container--wide biz-page-loading">
          <Loading text="Opening Izzy Clipz Business…" />
        </div>
      </main>
    </>
  );
}
