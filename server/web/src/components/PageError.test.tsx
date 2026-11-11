import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { renderApp } from '../test/api';

// A page whose own script can't be downloaded (the legal pages and Izzy Clipz Business load theirs
// only when they're opened) says so, under the nav and above the footer, instead of the whole site
// going blank; Try again loads the page afresh.

vi.mock('../legal/LegalPage', () => {
  throw new TypeError('Failed to fetch dynamically imported module: /assets/LegalPage-0ld0ne.js');
});
vi.mock('../business/BusinessApp', () => {
  throw new TypeError('Failed to fetch dynamically imported module: /assets/BusinessApp-0ld0ne.js');
});

/** React (in development) and the boundary each say what went wrong in the console: expected here. */
function quiet(): void {
  vi.spyOn(console, 'warn').mockImplementation(() => undefined);
  vi.spyOn(console, 'error').mockImplementation(() => undefined);
}

describe('a page whose script didn’t download', () => {
  it('says so, with Try again, and keeps the nav and the footer', async () => {
    const reload = vi.fn();
    vi.spyOn(window, 'location', 'get').mockReturnValue({ ...window.location, reload } as Location);
    quiet();
    renderApp('/privacy');
    const failed = await screen.findByTestId('page-failed');
    expect(within(failed).getByRole('heading', { level: 1 }).textContent).toBe("This page didn't load.");
    expect(failed.textContent).toContain('Check your connection and try again.');
    expect(within(failed).getByRole('link', { name: '(442) 341-3053' }).getAttribute('href')).toBe('tel:+14423413053');
    expect(document.title).toBe("This page didn't load · Izzy Clipz Barbershop");
    // Everything else is still there: the nav, and the footer with the four policies.
    expect(screen.getByRole('navigation', { name: 'Izzy Clipz' })).toBeTruthy();
    expect(within(screen.getByRole('contentinfo')).getByRole('navigation', { name: 'Legal' })).toBeTruthy();
    await userEvent.click(within(failed).getByRole('button', { name: 'Try again' }));
    expect(reload).toHaveBeenCalledTimes(1);
  });

  it('goes back to normal on another page', async () => {
    quiet();
    renderApp('/terms');
    await screen.findByTestId('page-failed');
    await userEvent.click(within(screen.getByRole('contentinfo')).getByRole('link', { name: 'Services and prices' }));
    expect(await screen.findByRole('heading', { level: 1, name: 'Services and prices' })).toBeTruthy();
    expect(screen.queryByTestId('page-failed')).toBeNull();
  });

  it('Izzy Clipz Business too, under its black bar', async () => {
    quiet();
    renderApp('/business/today');
    const failed = await screen.findByTestId('page-failed');
    expect(within(failed).getByRole('heading', { level: 1 }).textContent).toBe("This page didn't load.");
    expect(document.querySelector('.biz-globalbar')).not.toBeNull();
    expect(screen.getByRole('main').contains(failed)).toBe(true);
  });
});
