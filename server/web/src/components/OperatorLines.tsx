import { Link } from 'react-router-dom';
import type { Shop } from '../api/types';
import { NewTabLink } from './ui';

/** Where the refund policy is: the Terms' "4. Prices and paying" (its "Refunds" part). */
export const REFUND_POLICY_HREF = '/terms#4-prices-and-paying';

/** A part the owner hasn't given yet, marked as the draft documents mark theirs. */
function ToBeAdded({ what }: { what: string }) {
  return <mark className="operator__placeholder">To be added by the shop: {what}</mark>;
}

/**
 * Who runs the shop and where, how to get that by email, and where the refund policy is
 * (Business and Professions Code §17538(d); docs/legal/OWNER-CHECKLIST.md §3 item 20), in the app's
 * words (the Kit's `ShopInfo.operatedByLine` and `byEmailLine`): in the footer of every page and on
 * "Review and book", before any card is saved. The LLC's name and the shop's email come with the
 * shop's catalog (data/catalog.json, from the Kit); until the owner gives them, each shows as still
 * to be added, so it's never silently missing, and a strict build stops (tools/legal.ts).
 * `newTab` opens the Terms in a new tab, so a booking stays where it is.
 */
export function OperatorLines({ shop, className, testId, newTab = false }: { shop: Shop; className?: string; testId?: string; newTab?: boolean }) {
  const terms = newTab ? <NewTabLink href={REFUND_POLICY_HREF}>Terms of Service</NewTabLink> : <Link to={REFUND_POLICY_HREF}>Terms of Service</Link>;
  return (
    <div className={className} data-testid={testId}>
      <p>
        {shop.fullName} is operated by {shop.operatorName ?? <ToBeAdded what="the LLC's registered name" />}, {shop.address.lines.join(', ')}, United
        States.
      </p>
      <p>
        To get this information by email, email us at{' '}
        {shop.email ? <a href={`mailto:${shop.email}`}>{shop.email}</a> : <ToBeAdded what="the shop's email address" />} and we'll send it within 5
        days.
      </p>
      <p>Our refund policy is in section 4 of our {terms}.</p>
    </div>
  );
}
