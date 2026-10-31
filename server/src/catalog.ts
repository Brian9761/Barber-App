import { readFileSync } from 'node:fs';
import { z } from 'zod';
import { parseClock } from './time.js';

// The menu, team and hours, exported from IzzyClipzKit into data/catalog.json
// so the server and the apps book against exactly the same rules.

const clock = z.string().regex(/^\d{2}:\d{2}$/);
const priceKind = z.enum(['fixed', 'startingAt', 'includedWithCut']);

export const catalogSchema = z.object({
  timeZone: z.string().min(1),
  slotIntervalMinutes: z.number().int().positive(),
  leadTimeMinutes: z.number().int().nonnegative(),
  windowDays: z.number().int().nonnegative(),
  // Weekday keys like the Kit's Weekday: "1" = Sunday … "7" = Saturday. Missing days are closed.
  hours: z.record(z.enum(['1', '2', '3', '4', '5', '6', '7']), z.object({ opens: clock, closes: clock })),
  services: z.array(z.object({ id: z.string().min(1), name: z.string().min(1) })),
  barbers: z.array(z.object({ id: z.string().regex(/^[a-z0-9-]+$/), name: z.string().min(1) })),
  offerings: z.array(
    z.object({
      id: z.string().min(1),
      serviceId: z.string().min(1),
      barberId: z.string().min(1),
      durationMinutes: z.number().int().positive(),
      priceCents: z.number().int().nonnegative(),
      priceKind,
      priceLabel: z.string().min(1),
      name: z.string().min(1).optional(),
    }),
  ),
  firstAvailable: z.array(z.object({ serviceId: z.string().min(1), offeringIds: z.array(z.string().min(1)).min(1) })),
});

export type CatalogData = z.infer<typeof catalogSchema>;
export type Offering = CatalogData['offerings'][number];
export type Service = CatalogData['services'][number];
export type Barber = CatalogData['barbers'][number];
export type PriceKind = z.infer<typeof priceKind>;

export interface OpeningHours {
  /** Minutes since midnight. */
  opens: number;
  closes: number;
}

/** The catalog with lookups. Throws on load if the data is inconsistent. */
export class Catalog {
  readonly data: CatalogData;
  readonly timeZone: string;
  private readonly offeringsById = new Map<string, Offering>();
  private readonly servicesById = new Map<string, Service>();
  private readonly barbersById = new Map<string, Barber>();
  private readonly barberRanks = new Map<string, number>();
  private readonly firstAvailableByService = new Map<string, Offering[]>();
  private readonly hoursByWeekday = new Map<number, OpeningHours>();

  constructor(raw: unknown) {
    const data = catalogSchema.parse(raw);
    this.data = data;
    this.timeZone = data.timeZone;
    if (!isTimeZone(data.timeZone)) throw new Error(`Unknown time zone ${data.timeZone}`);
    for (const s of data.services) unique(this.servicesById, s.id, s, 'service');
    data.barbers.forEach((b, i) => {
      unique(this.barbersById, b.id, b, 'barber');
      this.barberRanks.set(b.id, i);
    });
    for (const o of data.offerings) {
      unique(this.offeringsById, o.id, o, 'offering');
      if (!this.servicesById.has(o.serviceId)) throw new Error(`Offering ${o.id} has unknown service ${o.serviceId}`);
      if (!this.barbersById.has(o.barberId)) throw new Error(`Offering ${o.id} has unknown barber ${o.barberId}`);
    }
    for (const fa of data.firstAvailable) {
      const offerings = fa.offeringIds.map((id) => {
        const o = this.offeringsById.get(id);
        if (!o || o.serviceId !== fa.serviceId) throw new Error(`firstAvailable for ${fa.serviceId} lists ${id}`);
        return o;
      });
      if (new Set(offerings.map((o) => o.barberId)).size !== offerings.length) {
        throw new Error(`firstAvailable for ${fa.serviceId} lists a barber twice`);
      }
      unique(this.firstAvailableByService, fa.serviceId, offerings, 'firstAvailable service');
    }
    for (const [key, h] of Object.entries(data.hours)) {
      const opens = parseClock(h.opens);
      const closes = parseClock(h.closes);
      if (opens >= closes) throw new Error(`Hours for weekday ${key} close before they open`);
      this.hoursByWeekday.set(Number(key), { opens, closes });
    }
  }

  get slotIntervalMinutes(): number {
    return this.data.slotIntervalMinutes;
  }
  get leadTimeMinutes(): number {
    return this.data.leadTimeMinutes;
  }
  get windowDays(): number {
    return this.data.windowDays;
  }
  get barbers(): readonly Barber[] {
    return this.data.barbers;
  }

  offering(id: string): Offering | undefined {
    return this.offeringsById.get(id);
  }
  service(id: string): Service | undefined {
    return this.servicesById.get(id);
  }
  barber(id: string): Barber | undefined {
    return this.barbersById.get(id);
  }
  /** Team order, for "ties go to catalog order" and sorting barber ids. */
  barberRank(id: string): number {
    return this.barberRanks.get(id) ?? Number.MAX_SAFE_INTEGER;
  }
  /** The offerings an "any barber" booking chooses from, in team order. */
  firstAvailable(serviceId: string): readonly Offering[] | undefined {
    return this.firstAvailableByService.get(serviceId);
  }
  /** Opening hours for a Kit weekday (1 = Sunday … 7 = Saturday), or undefined when closed. */
  hours(weekday: number): OpeningHours | undefined {
    return this.hoursByWeekday.get(weekday);
  }
}

function unique<V>(map: Map<string, V>, id: string, value: V, kind: string): void {
  if (map.has(id)) throw new Error(`Duplicate ${kind} ${id}`);
  map.set(id, value);
}

function isTimeZone(zone: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: zone });
    return true;
  } catch {
    return false;
  }
}

let shared: Catalog | undefined;

/** The bundled data/catalog.json, loaded once. */
export function loadCatalog(): Catalog {
  shared ??= new Catalog(JSON.parse(readFileSync(new URL('../data/catalog.json', import.meta.url), 'utf8')));
  return shared;
}
