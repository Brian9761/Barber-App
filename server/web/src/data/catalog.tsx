import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { api, errorMessage } from '../api/client';
import type { Catalog } from '../api/types';
import { FALLBACK_SHOP } from './fallback';

// The catalog (menu, team, hours, booking rules and the shop's details), asked
// for once per visit. Every page reads it from here.

export type CatalogState =
  | { status: 'loading' }
  | { status: 'ready'; catalog: Catalog }
  | { status: 'error'; message: string; retry: () => void };

const CatalogContext = createContext<CatalogState>({ status: 'loading' });

export function CatalogProvider({ children, initial }: { children: ReactNode; initial?: Catalog }) {
  const [state, setState] = useState<CatalogState>(initial ? { status: 'ready', catalog: initial } : { status: 'loading' });
  const [attempt, setAttempt] = useState(0);
  const retry = useCallback(() => {
    setState({ status: 'loading' });
    setAttempt((n) => n + 1);
  }, []);

  useEffect(() => {
    if (initial) return;
    const controller = new AbortController();
    api
      .catalog(controller.signal)
      .then((catalog) => setState({ status: 'ready', catalog }))
      .catch((error: unknown) => {
        if (controller.signal.aborted) return;
        setState({ status: 'error', message: errorMessage(error), retry });
      });
    return () => controller.abort();
  }, [attempt, initial, retry]);

  return <CatalogContext.Provider value={state}>{children}</CatalogContext.Provider>;
}

export function useCatalogState(): CatalogState {
  return useContext(CatalogContext);
}

/** The catalog once it's here, or null. */
export function useCatalog(): Catalog | null {
  const state = useCatalogState();
  return state.status === 'ready' ? state.catalog : null;
}

/** How to reach the shop: from the catalog, or the fallback while it loads. */
export function useShopContact() {
  const catalog = useCatalog();
  return useMemo(
    () =>
      catalog
        ? {
            name: catalog.shop.name,
            fullName: catalog.shop.fullName,
            phone: catalog.shop.phone,
            addressLines: catalog.shop.address.lines,
            instagram: catalog.shop.instagram,
            googleMapsUrl: catalog.shop.googleMapsUrl,
          }
        : {
            name: FALLBACK_SHOP.name,
            fullName: FALLBACK_SHOP.fullName,
            phone: FALLBACK_SHOP.phone,
            addressLines: [...FALLBACK_SHOP.addressLines],
            instagram: FALLBACK_SHOP.instagram,
            googleMapsUrl: FALLBACK_SHOP.googleMapsUrl,
          },
    [catalog],
  );
}
