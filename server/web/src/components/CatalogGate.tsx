import type { ReactNode } from 'react';
import type { Catalog } from '../api/types';
import { useCatalogState } from '../data/catalog';
import { ErrorState, Loading } from './ui';

/** Shows the page once the catalog is here; meanwhile a calm "Loading", or what to do if it can't load. */
export function CatalogGate({ children }: { children: (catalog: Catalog) => ReactNode }) {
  const state = useCatalogState();
  if (state.status === 'ready') return <>{children(state.catalog)}</>;
  if (state.status === 'error') {
    return (
      <div className="container">
        <ErrorState title="This page couldn't load" message={state.message} onRetry={state.retry} />
      </div>
    );
  }
  return (
    <div className="container page-loading">
      <Loading text="Loading…" />
    </div>
  );
}
