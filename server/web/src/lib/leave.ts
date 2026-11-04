/** Leaves the site for another page (Stripe's card page). On its own so tests can see where it would go. */
export function leaveTo(url: string): void {
  window.location.assign(url);
}
