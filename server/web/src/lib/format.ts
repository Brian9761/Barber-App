// Words and numbers formatted the way the apps show them (IzzyClipzKit's Price,
// DurationText and the booking copy), by hand, so they read the same in every
// browser and locale.

export type PriceKind = 'fixed' | 'startingAt' | 'includedWithCut';

export interface PricedItem {
  priceCents: number;
  priceKind: PriceKind;
}

/** "$35", "$7.50", "$0.50" (the Kit's `Price.currencyString`). */
export function money(cents: number): string {
  const dollars = Math.floor(cents / 100);
  const rest = cents % 100;
  return rest === 0 ? `$${dollars}` : `$${dollars}.${String(rest).padStart(2, '0')}`;
}

/** A menu item's own label: "$35", "From $80", "Included with cut" (the Kit's `Price.label`). */
export function priceLabel(item: PricedItem): string {
  switch (item.priceKind) {
    case 'includedWithCut':
      return 'Included with cut';
    case 'startingAt':
      return `From ${money(item.priceCents)}`;
    default:
      return money(item.priceCents);
  }
}

/**
 * Several barbers' prices for one choice, as the app's booking rows show them
 * (the Kit's `Price.summary`): "$35", "$55–$60", "From $80", "Included with cut".
 */
export function priceSummary(items: readonly PricedItem[]): string {
  const charged = items.filter((i) => i.priceKind !== 'includedWithCut').map((i) => i.priceCents);
  if (charged.length === 0) return items.length === 0 ? '' : 'Included with cut';
  const lowest = Math.min(...charged);
  const highest = Math.max(...charged);
  if (items.some((i) => i.priceKind === 'startingAt')) return `From ${money(lowest)}`;
  return lowest === highest ? money(lowest) : `${money(lowest)}–${money(highest)}`;
}

/**
 * A service's price across the barbers who offer it, for the menu pages: "$40"
 * when it's the same everywhere, otherwise "From $35" (also for a "starting
 * at" price), or "Included with cut".
 */
export function fromPrice(items: readonly PricedItem[]): string {
  const charged = items.filter((i) => i.priceKind !== 'includedWithCut').map((i) => i.priceCents);
  if (charged.length === 0) return items.length === 0 ? '' : 'Included with cut';
  const lowest = Math.min(...charged);
  const varies = new Set(charged).size > 1 || items.some((i) => i.priceKind === 'startingAt');
  return varies ? `From ${money(lowest)}` : money(lowest);
}

/** "15 min", "1 hr", "1 hr 15 min" (the Kit's `DurationText.short`). */
export function durationLabel(minutes: number): string {
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  if (hours === 0) return `${rest} min`;
  if (rest === 0) return `${hours} hr`;
  return `${hours} hr ${rest} min`;
}

/** "45 min", "30–45 min", "45 min – 1 hr" (the Kit's `DurationText.range`). */
export function durationRange(minutes: readonly number[]): string {
  if (minutes.length === 0) return '';
  const shortest = Math.min(...minutes);
  const longest = Math.max(...minutes);
  if (shortest === longest) return durationLabel(shortest);
  if (longest < 60) return `${shortest}–${longest} min`;
  return `${durationLabel(shortest)} – ${durationLabel(longest)}`;
}

/** "Flowxbori, Cristian or Julian" (the booking copy's list). */
export function list(names: readonly string[], conjunction = 'or'): string {
  if (names.length <= 1) return names[0] ?? '';
  return `${names.slice(0, -1).join(', ')} ${conjunction} ${names[names.length - 1]}`;
}

/** "30 minutes", "1 hour", "90 minutes", "2 hours" (the server's `windowLabel`). */
export function windowLabel(minutes: number): string {
  if (minutes % 60 !== 0) return `${minutes} minutes`;
  const hours = minutes / 60;
  return hours === 1 ? '1 hour' : `${hours} hours`;
}

/** "1 service", "3 services". */
export function plural(count: number, one: string, many = `${one}s`): string {
  return `${count} ${count === 1 ? one : many}`;
}

/** Stripe's brand value as people say it: "Visa", "American Express"; "Card" for one it doesn't know. */
export function cardBrandName(brand: string): string {
  switch (brand.toLowerCase()) {
    case 'visa':
      return 'Visa';
    case 'mastercard':
      return 'Mastercard';
    case 'amex':
    case 'american_express':
      return 'American Express';
    case 'discover':
      return 'Discover';
    case 'diners':
    case 'diners_club':
      return 'Diners Club';
    case 'jcb':
      return 'JCB';
    case 'unionpay':
    case 'union_pay':
      return 'UnionPay';
    case 'cartes_bancaires':
      return 'Cartes Bancaires';
    case 'eftpos_au':
    case 'eftpos_australia':
      return 'eftpos';
    case 'link':
      return 'Link';
    default:
      return 'Card';
  }
}

/** "Visa •••• 4242". */
export function cardLabel(card: { brand: string; last4: string }): string {
  return `${cardBrandName(card.brand)} •••• ${card.last4}`;
}
