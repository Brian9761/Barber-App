// Lookups over the catalog, in the same orders the apps use (IzzyClipzKit's Catalog).

import type { Catalog, CatalogBarber, CatalogService, Offering } from '../api/types';
import { durationRange, fromPrice, money, priceSummary } from './format';

export function serviceById(catalog: Catalog, id: string | null | undefined): CatalogService | undefined {
  return id ? catalog.services.find((s) => s.id === id) : undefined;
}

export function barberById(catalog: Catalog, id: string | null | undefined): CatalogBarber | undefined {
  return id ? catalog.barbers.find((b) => b.id === id) : undefined;
}

export function offeringById(catalog: Catalog, id: string | null | undefined): Offering | undefined {
  return id ? catalog.offerings.find((o) => o.id === id) : undefined;
}

function barberRank(catalog: Catalog, id: string): number {
  const index = catalog.barbers.findIndex((b) => b.id === id);
  return index === -1 ? Number.MAX_SAFE_INTEGER : index;
}

function serviceRank(catalog: Catalog, id: string): number {
  const index = catalog.services.findIndex((s) => s.id === id);
  return index === -1 ? Number.MAX_SAFE_INTEGER : index;
}

/** Every barber's version of a service: cheapest first, then team order, then shortest. */
export function offeringsForService(catalog: Catalog, serviceId: string): Offering[] {
  return catalog.offerings
    .filter((o) => o.serviceId === serviceId)
    .sort(
      (a, b) =>
        a.priceCents - b.priceCents ||
        barberRank(catalog, a.barberId) - barberRank(catalog, b.barberId) ||
        a.durationMinutes - b.durationMinutes,
    );
}

/** Everything a barber offers, in menu order. */
export function offeringsForBarber(catalog: Catalog, barberId: string): Offering[] {
  return catalog.offerings
    .filter((o) => o.barberId === barberId)
    .sort(
      (a, b) =>
        serviceRank(catalog, a.serviceId) - serviceRank(catalog, b.serviceId) ||
        a.priceCents - b.priceCents ||
        a.durationMinutes - b.durationMinutes,
    );
}

/** The barbers who offer a service, in team order. */
export function barbersForService(catalog: Catalog, serviceId: string): CatalogBarber[] {
  const ids = new Set(catalog.offerings.filter((o) => o.serviceId === serviceId).map((o) => o.barberId));
  return catalog.barbers.filter((b) => ids.has(b.id));
}

/** The services a barber offers, in menu order. */
export function servicesForBarber(catalog: Catalog, barberId: string): CatalogService[] {
  const ids = new Set(catalog.offerings.filter((o) => o.barberId === barberId).map((o) => o.serviceId));
  return catalog.services.filter((s) => ids.has(s.id));
}

export interface AnyBarberOption {
  serviceId: string;
  offerings: Offering[];
  barbers: CatalogBarber[];
  /** "$35", "$55–$60". */
  priceLabel: string;
  /** "45 min", "30–45 min". */
  durationLabel: string;
}

/** Booking a service with whoever is free first, when at least two barbers share it. */
export function anyBarberOption(catalog: Catalog, serviceId: string): AnyBarberOption | null {
  const entry = catalog.firstAvailable.find((f) => f.serviceId === serviceId);
  if (!entry) return null;
  const offerings = entry.offeringIds.map((id) => offeringById(catalog, id)).filter((o): o is Offering => o !== undefined);
  if (offerings.length < 2) return null;
  return {
    serviceId,
    offerings,
    barbers: offerings.map((o) => barberById(catalog, o.barberId)).filter((b): b is CatalogBarber => b !== undefined),
    priceLabel: priceSummary(offerings),
    durationLabel: durationRange(offerings.map((o) => o.durationMinutes)),
  };
}

/** "From $35", "$80", "Included with cut": the service's price across its barbers. */
export function servicePrice(catalog: Catalog, serviceId: string): string {
  return fromPrice(catalog.offerings.filter((o) => o.serviceId === serviceId));
}

/** "45 min – 1 hr": the service's length across its barbers. */
export function serviceDuration(catalog: Catalog, serviceId: string): string {
  return durationRange(catalog.offerings.filter((o) => o.serviceId === serviceId).map((o) => o.durationMinutes));
}

/** "$35–$45": the service's price range, as the barber step's subtitle says it. */
export function servicePriceRange(catalog: Catalog, serviceId: string): string {
  return priceSummary(catalog.offerings.filter((o) => o.serviceId === serviceId));
}

export interface CategoryGroup {
  title: string;
  /** "haircuts", "color-texture": for in-page links. */
  anchor: string;
  services: CatalogService[];
}

/** The services under their menu categories, in menu order. */
export function categories(catalog: Catalog, services: readonly CatalogService[] = catalog.services): CategoryGroup[] {
  const groups: CategoryGroup[] = [];
  for (const service of services) {
    let group = groups.find((g) => g.title === service.category);
    if (!group) {
      group = { title: service.category, anchor: anchorOf(service.category), services: [] };
      groups.push(group);
    }
    group.services.push(service);
  }
  return groups;
}

function anchorOf(title: string): string {
  return title
    .toLowerCase()
    .replace(/&/g, ' ')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
}

/** The tile color the apps give each barber by their place on the team. */
export function monogramTone(catalog: Catalog, barberId: string): 'bone' | 'blue' | 'ink' {
  const index = Math.max(0, catalog.barbers.findIndex((b) => b.id === barberId));
  switch (index % 5) {
    case 0:
    case 3:
      return 'bone';
    case 2:
      return 'ink';
    default:
      return 'blue';
  }
}

/** "Haircut $45", or "Haircut from $35" for a barber with more than one haircut price. */
export function haircutLine(catalog: Catalog, barberId: string): string | null {
  const prices = catalog.offerings.filter((o) => o.barberId === barberId && o.serviceId === 'haircut');
  if (prices.length === 0) return null;
  const lowest = Math.min(...prices.map((o) => o.priceCents));
  const varies = new Set(prices.map((o) => o.priceCents)).size > 1 || prices.some((o) => o.priceKind === 'startingAt');
  return varies ? `Haircut from ${money(lowest)}` : `Haircut ${money(lowest)}`;
}
