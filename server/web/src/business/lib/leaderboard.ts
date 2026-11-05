// The leaderboard by the metric the owner picks: sales (the server's own order), services,
// products or clients served. Highest first, then by name; barbers with the same value
// share a place, and the next place skips (1, 1, 3).

import type { LeaderboardEntry } from '../types';
import { moneyWithCommas } from './money';

export type Metric = 'sales' | 'services' | 'products' | 'clients';

export const METRICS: { id: Metric; label: string }[] = [
  { id: 'sales', label: 'Sales' },
  { id: 'services', label: 'Services' },
  { id: 'products', label: 'Products' },
  { id: 'clients', label: 'Clients served' },
];

export function metricValue(entry: LeaderboardEntry, metric: Metric): number {
  switch (metric) {
    case 'sales':
      return entry.salesCents;
    case 'services':
      return entry.servicesCount;
    case 'products':
      return entry.productsCount;
    case 'clients':
      return entry.clientsServed;
  }
}

/** "$215", "3 services", "1 product", "12 clients". */
export function metricLabel(entry: LeaderboardEntry, metric: Metric): string {
  const value = metricValue(entry, metric);
  switch (metric) {
    case 'sales':
      return moneyWithCommas(value);
    case 'services':
      return `${value} ${value === 1 ? 'service' : 'services'}`;
    case 'products':
      return `${value} ${value === 1 ? 'product' : 'products'}`;
    case 'clients':
      return `${value} ${value === 1 ? 'client' : 'clients'}`;
  }
}

export interface Ranked {
  entry: LeaderboardEntry;
  place: number;
  value: number;
}

/** The leaderboard in `metric`'s order. For sales it's the server's order and places, as they are. */
export function rankBy(entries: readonly LeaderboardEntry[], metric: Metric): Ranked[] {
  if (metric === 'sales') return entries.map((entry) => ({ entry, place: entry.rank, value: entry.salesCents }));
  const sorted = [...entries].sort((a, b) => metricValue(b, metric) - metricValue(a, metric) || a.name.localeCompare(b.name, 'en'));
  let place = 0;
  return sorted.map((entry, i) => {
    const value = metricValue(entry, metric);
    const before = sorted[i - 1];
    if (!before || metricValue(before, metric) !== value) place = i + 1;
    return { entry, place, value };
  });
}
