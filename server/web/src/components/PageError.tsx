import { Component, type ErrorInfo, type ReactNode } from 'react';
import { CallLink } from './ui';
import { usePageMeta } from './usePageMeta';

/**
 * What a page that couldn't be drawn says instead: calm, with Try again (which loads the page
 * afresh) and the shop's number. The nav and the footer stay around it.
 */
export function PageLoadFailed({ onRetry }: { onRetry: () => void }) {
  usePageMeta("This page didn't load", "This page didn't load. Check your connection and try again, or call the shop.");
  return (
    <section className="band page-failed" aria-labelledby="page-failed-title" data-testid="page-failed">
      <div className="container container--narrow page-failed__inner">
        <h1 id="page-failed-title">This page didn't load.</h1>
        <p className="lead secondary">Check your connection and try again.</p>
        <div>
          <button type="button" className="button button--primary" onClick={onRetry}>
            Try again
          </button>
        </div>
        <p className="secondary">
          To book or ask anything, call the shop at <CallLink className="inline-link nowrap" />.
        </p>
      </div>
    </section>
  );
}

interface PageErrorBoundaryProps {
  /** The page's address: going to another page tries again. */
  resetKey: string;
  /** What shows instead, given a way to try again. */
  fallback: (retry: () => void) => ReactNode;
  children: ReactNode;
  /** Loads the page afresh; the tests pass their own. */
  reload?: () => void;
}

/**
 * Catches a page that couldn't be drawn. Most often that's its own script, which loads only when
 * it's opened (the legal pages, Izzy Clipz Business) and couldn't be downloaded: no connection
 * before the site was kept for offline use, or a new version replaced the old files. Without this,
 * React takes the whole site down to a blank screen; with it, the page says so and the rest stays.
 */
export class PageErrorBoundary extends Component<PageErrorBoundaryProps, { failed: boolean }> {
  override state = { failed: false };

  static getDerivedStateFromError(): { failed: boolean } {
    return { failed: true };
  }

  override componentDidCatch(error: unknown, info: ErrorInfo): void {
    // Said once in the console for whoever looks into it; the visitor sees the calm message.
    console.warn('A page could not be drawn', error, info.componentStack);
  }

  override componentDidUpdate(previous: PageErrorBoundaryProps): void {
    if (this.state.failed && previous.resetKey !== this.props.resetKey) this.setState({ failed: false });
  }

  override render(): ReactNode {
    if (!this.state.failed) return this.props.children;
    return this.props.fallback(this.props.reload ?? (() => window.location.reload()));
  }
}
