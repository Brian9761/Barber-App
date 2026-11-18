import { Link } from 'react-router-dom';
import type { Shop } from '../api/types';
import { NewTabLink } from './ui';

/** The refund policy: the "Refunds" part of the Terms' "4. Prices and paying", which has its own anchor. */
export const REFUNDS_HREF = '/terms#refunds';
/** What links to it say, next to the Cancellation & No-Show Policy (OWNER-CHECKLIST §3 item 20). */
export const REFUNDS_LABEL = 'Refunds';

/** The LLC's registered name that runs the shop, or null until the owner gives it (the catalog has ""). */
export function legalNameOf(shop: Pick<Shop, 'legalName'>): string | null {
  return shop.legalName?.trim() || null;
}

/** The shop's email address, or null until the shop has one (the catalog has ""). */
export function emailOf(shop: Pick<Shop, 'email'>): string | null {
  return shop.email?.trim() || null;
}

/**
 * Who runs the shop and where, in the app's words (the Kit's `ShopInfo.operatedByLine`): "Izzy Clipz
 * Barbershop is operated by <legalName>, 1919 Mission Ave, Ste 105, Oceanside, CA 92058, United
 * States." Until the owner gives the LLC's name, only what's known, nothing made up: "Izzy Clipz
 * Barbershop, 1919 Mission Ave, Ste 105, Oceanside, CA 92058, United States."
 */
export function operatedByLine(shop: Pick<Shop, 'fullName' | 'address' | 'legalName'>): string {
  const place = `${shop.address.lines.join(', ')}, United States.`;
  const legalName = legalNameOf(shop);
  return legalName ? `${shop.fullName} is operated by ${legalName}, ${place}` : `${shop.fullName}, ${place}`;
}

/**
 * Who runs the shop and where, and how to get that by email (Business and Professions Code
 * §17538(d); docs/legal/OWNER-CHECKLIST.md §3 item 20), in the app's words (the Kit's
 * `ShopInfo.operatedByLine` and `byEmailLine`): in the footer of every page and on "Review and
 * book", before any card is saved. The LLC's name and the shop's email come with the shop's catalog
 * (data/catalog.json, from the Kit). Until the owner gives them, it says what's known (the shop and
 * its address) and leaves the rest out, and a strict build stops (tools/legal.ts).
 *
 * `policyLinks` adds the Cancellation & No-Show Policy with "Refunds" (the refund policy) next to
 * it, for "Review and book" (the footer has both in its row of policies). `newTab` opens them in a
 * new tab, so a booking stays where it is.
 */
export function OperatorLines({
  shop,
  className,
  testId,
  policyLinks = false,
  newTab = false,
}: {
  shop: Shop;
  className?: string;
  testId?: string;
  policyLinks?: boolean;
  newTab?: boolean;
}) {
  const email = emailOf(shop);
  const link = (href: string, label: string) => (newTab ? <NewTabLink href={href}>{label}</NewTabLink> : <Link to={href}>{label}</Link>);
  return (
    <div className={className} data-testid={testId}>
      <p>{operatedByLine(shop)}</p>
      {email ? (
        <p>
          To get this information by email, email us at <a href={`mailto:${email}`}>{email}</a> and we'll send it within 5 days.
        </p>
      ) : null}
      {policyLinks ? (
        <p className="operator__policies" data-testid={testId ? `${testId}-policies` : undefined}>
          {link('/cancellation-policy', 'Cancellation & No-Show Policy')}
          <span aria-hidden="true"> · </span>
          {link(REFUNDS_HREF, REFUNDS_LABEL)}
        </p>
      ) : null}
    </div>
  );
}
