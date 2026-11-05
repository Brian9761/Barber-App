// Amounts as the owner types them ("40", "17.50", "$25", "1,200") and as they're shown.

import { money } from '../../lib/format';

/** The most a sale (or one price) can be: $10,000. */
export const MAX_CENTS = 1_000_000;

/**
 * Cents from what was typed, or null when it isn't an amount: digits with an optional
 * dollar sign, thousands commas and at most two decimals.
 */
export function parseMoney(text: string): number | null {
  const cleaned = text
    .trim()
    .replace(/^\$\s*/, '')
    .replace(/,/g, '');
  if (!/^\d{1,7}(\.\d{0,2})?$/.test(cleaned) && !/^\.\d{1,2}$/.test(cleaned)) return null;
  const [dollars = '0', cents = ''] = cleaned.split('.');
  return Number(dollars || '0') * 100 + Number((cents + '00').slice(0, 2));
}

/** "40", "17.50": an amount as it's edited (no dollar sign, no needless ".00"). */
export function editableMoney(cents: number): string {
  const dollars = Math.floor(cents / 100);
  const rest = cents % 100;
  return rest === 0 ? String(dollars) : `${dollars}.${String(rest).padStart(2, '0')}`;
}

/** "$1,240", "$17.50": with thousands commas, for totals. */
export function moneyWithCommas(cents: number): string {
  const sign = cents < 0 ? '-' : '';
  const abs = Math.abs(cents);
  const dollars = Math.floor(abs / 100)
    .toString()
    .replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  const rest = abs % 100;
  return rest === 0 ? `${sign}$${dollars}` : `${sign}$${dollars}.${String(rest).padStart(2, '0')}`;
}

/** "$1.2K", "$12K", "$1.3M" for chart axes; plain dollars under $1,000. */
export function compactMoney(cents: number): string {
  const dollars = cents / 100;
  if (dollars < 1000) return money(Math.round(dollars) * 100);
  if (dollars < 1_000_000) {
    const k = dollars / 1000;
    return `$${k < 10 ? k.toFixed(1).replace(/\.0$/, '') : Math.round(k)}K`;
  }
  const m = dollars / 1_000_000;
  return `$${m < 10 ? m.toFixed(1).replace(/\.0$/, '') : Math.round(m)}M`;
}

/** "12%", "100%": a share, rounded to the whole percent. */
export function percent(ratio: number): string {
  return `${Math.round(ratio * 100)}%`;
}

/**
 * The price an appointment was booked at, from its label ("$35", "From $80", "Included with
 * cut"): the appointment JSON gives the label, and the server checks it out at that price.
 */
export function priceFromLabel(label: string): number | null {
  if (/included/i.test(label)) return 0;
  const match = /\$(\d[\d,]*)(?:\.(\d{2}))?/.exec(label);
  if (!match) return null;
  return Number(match[1]!.replace(/,/g, '')) * 100 + Number(match[2] ?? '0');
}
