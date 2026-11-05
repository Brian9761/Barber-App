import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { times } from '../test/text';
import { availability, catalog, mockApi, policy35, policyNotRequired, renderApp } from '../test/api';
import { loadDraft } from './flow';

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date('2026-11-03T16:00:00Z')); // Tuesday 8 AM at the shop
});

afterEach(() => {
  vi.useRealTimers();
});

const title = () => screen.getByRole('heading', { level: 1 }).textContent;
const stepCount = () => screen.getByTestId('step-count').textContent;
const summaryText = () => screen.getByTestId('summary-card').textContent ?? '';

describe('booking, one question at a time', () => {
  it('takes a haircut with any barber to Review', async () => {
    const api = mockApi([
      ['GET /api/availability', { body: availability }],
      ['GET /api/no-show-policy', { body: policyNotRequired }],
    ]);
    renderApp('/book');

    expect(title()).toBe('Pick a service');
    expect(stepCount()).toBe('Step 1 of 5');
    await userEvent.click(screen.getByTestId('service-haircut'));

    expect(title()).toBe('Pick a barber');
    expect(stepCount()).toBe('Step 2 of 5');
    const any = screen.getByTestId('any-barber');
    expect(any.textContent).toContain('Whoever is free first: Flowxbori, Cristian or Julian');
    await userEvent.click(any);

    expect(title()).toBe('Pick a day and time');
    // The first day with openings is picked to start with: today.
    expect(await screen.findByRole('heading', { level: 2, name: 'Tuesday, November 3' })).toBeTruthy();
    const continueButton = screen.getByRole('button', { name: 'Continue' }) as HTMLButtonElement;
    expect(continueButton.disabled).toBe(true);
    // Screen readers hear one short line for the day, not every time read out.
    await waitFor(() => expect(screen.getByTestId('times-status').textContent).toMatch(/^\d+ open times? on Tuesday, November 3\.$/));
    expect(screen.getByTestId('times-status').getAttribute('role')).toBe('status');
    expect(document.querySelector('.times')!.hasAttribute('aria-live')).toBe(false);
    await userEvent.click(screen.getByTestId('time-2026-11-03T19:00:00Z'));
    expect(screen.getByTestId('time-2026-11-03T19:00:00Z').getAttribute('aria-pressed')).toBe('true');
    expect(summaryText()).toContain(times('Tue, Nov 3 at 11 AM'));
    await userEvent.click(continueButton);

    const [request] = api.calls.filter((c) => c.path === '/api/availability');
    expect(new URLSearchParams(request!.search).toString()).toBe('serviceId=haircut&barberId=any&from=2026-11-03&days=14');

    expect(title()).toBe('Your details');
    await userEvent.type(screen.getByLabelText('Name'), 'Ana Flores');
    await userEvent.type(screen.getByLabelText('Mobile number'), '442 555 0123');
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }));

    expect(title()).toBe('Review and book');
    expect(stepCount()).toBe('Step 5 of 5');
    const review = screen.getByRole('main');
    expect(review.textContent).toContain('Any barber');
    expect(review.textContent).toContain('Ana Flores');
    // The number, as people write it.
    expect(review.textContent).toContain('(442) 555-0123');
    expect(loadDraft()).toMatchObject({ serviceId: 'haircut', choice: { kind: 'any' }, start: '2026-11-03T19:00:00Z' });
  });

  it('keeps the picked time while the client looks at other days', async () => {
    mockApi([
      ['GET /api/availability', { body: availability }],
      ['GET /api/no-show-policy', { body: policyNotRequired }],
    ]);
    renderApp('/book');
    await userEvent.click(screen.getByTestId('service-haircut'));
    await userEvent.click(screen.getByTestId('any-barber'));
    await userEvent.click(await screen.findByTestId('time-2026-11-03T19:00:00Z'));

    // Another day's times show, and the time picked on Tuesday is still the one.
    await userEvent.click(screen.getByTestId('day-2026-11-04'));
    expect(await screen.findByRole('heading', { level: 2, name: 'Wednesday, November 4' })).toBeTruthy();
    expect(screen.getByTestId('time-2026-11-04T19:00:00Z').getAttribute('aria-pressed')).toBe('false');
    const continueButton = screen.getByRole('button', { name: 'Continue' }) as HTMLButtonElement;
    expect(continueButton.disabled).toBe(false);
    expect(screen.getByText('Tue, Nov 3 at 11 AM', { selector: '.step-actions__note' })).toBeTruthy();
    await userEvent.click(continueButton);
    expect(title()).toBe('Your details');
    expect(loadDraft()).toMatchObject({ start: '2026-11-03T19:00:00Z' });
  });

  it('says what’s missing in the details, and puts the cursor there', async () => {
    mockApi([
      ['GET /api/availability', { body: availability }],
      ['GET /api/no-show-policy', { body: policyNotRequired }],
    ]);
    renderApp('/book');
    await userEvent.click(screen.getByTestId('service-haircut'));
    await userEvent.click(screen.getByTestId('any-barber'));
    await userEvent.click(await screen.findByTestId('time-2026-11-03T19:00:00Z'));
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }));

    await userEvent.type(screen.getByLabelText('Mobile number'), '555-0123');
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }));
    expect(title()).toBe('Your details');
    expect(screen.getByText("Enter your name so the shop knows who's coming.")).toBeTruthy();
    expect(screen.getByText('Enter a 10-digit US number, like (442) 341-3053.')).toBeTruthy();
    expect(document.activeElement).toBe(screen.getByLabelText('Name'));
    expect(screen.getByLabelText('Name').getAttribute('aria-invalid')).toBe('true');
  });

  it('goes straight to the times when the barber was picked first', async () => {
    mockApi([
      ['GET /api/availability', { body: availability }],
      ['GET /api/no-show-policy', { body: policyNotRequired }],
    ]);
    renderApp('/book?barber=carlos-rafael');

    expect(title()).toBe('Pick a service');
    expect(screen.getByText("Everything Carlos offers, at Carlos's own prices. No payment needed to book.")).toBeTruthy();
    const carlosHaircut = catalog.offerings.find((o) => o.barberId === 'carlos-rafael' && o.serviceId === 'haircut')!;
    await userEvent.click(screen.getByTestId(`offering-${carlosHaircut.id}`));
    expect(title()).toBe('Pick a day and time');
    expect(summaryText()).toContain('Carlos');
    expect(summaryText()).toContain('$45');
  });

  it('opens with the service already picked from the menu pages', async () => {
    renderApp('/book?service=vip');
    // Straight to who does it.
    await waitFor(() => expect(title()).toBe('Pick a barber'));
    expect(summaryText()).toContain('VIP');
  });

  it('keeps every choice going back, and the page’s Back goes back a step', async () => {
    mockApi([
      ['GET /api/availability', { body: availability }],
      ['GET /api/no-show-policy', { body: policyNotRequired }],
    ]);
    renderApp('/book');
    await userEvent.click(screen.getByTestId('service-haircut'));
    await userEvent.click(screen.getByTestId('any-barber'));
    await userEvent.click(await screen.findByTestId('time-2026-11-03T19:00:00Z'));

    await userEvent.click(screen.getByRole('button', { name: 'Back' }));
    expect(title()).toBe('Pick a barber');
    expect(screen.getByTestId('any-barber').getAttribute('aria-current')).toBe('true');
    await userEvent.click(screen.getByRole('button', { name: 'Back' }));
    expect(title()).toBe('Pick a service');
    expect(screen.getByTestId('service-haircut').getAttribute('aria-current')).toBe('true');

    // The same choices again keep the time.
    await userEvent.click(screen.getByTestId('service-haircut'));
    await userEvent.click(screen.getByTestId('any-barber'));
    expect(await screen.findByTestId('time-2026-11-03T19:00:00Z')).toBeTruthy();
    await waitFor(() => expect(screen.getByTestId('time-2026-11-03T19:00:00Z').getAttribute('aria-pressed')).toBe('true'));
  });

  it('shows the shop’s fee notice on the times when the booking needs a card', async () => {
    vi.setSystemTime(new Date('2026-11-03T17:15:00Z')); // 9:15 AM
    mockApi([
      ['GET /api/availability', { body: availability }],
      ['GET /api/no-show-policy', { body: policy35 }],
    ]);
    renderApp('/book');
    await userEvent.click(screen.getByTestId('service-haircut'));
    await userEvent.click(screen.getByTestId('any-barber'));

    const warning = await screen.findByTestId('fee-warning');
    expect(warning.textContent).toContain(policy35.warning!.title);
    expect(warning.textContent).toContain(policy35.warning!.message);
    // The shop's words say "in the app": the website says its own cancelling counts the same.
    expect(warning.textContent).toContain('Cancelling on this website, under My appointments, works the same as cancelling in the app.');
    // The whole policy is a click away, in a new tab, so the booking stays where it is.
    const policyLink = within(warning).getByRole('link', { name: /^Read the Cancellation & No-Show Policy\s*\(opens in a new tab\)$/ });
    expect([policyLink.getAttribute('href'), policyLink.getAttribute('target')]).toEqual(['/cancellation-policy', '_blank']);
    // 10:30 is more than an hour away: nothing more to say. 10 AM is inside the hour: it says so.
    await userEvent.click(await screen.findByTestId('time-2026-11-03T18:30:00Z'));
    expect(warning.textContent).not.toContain('less than 1 hour away');
    await userEvent.click(screen.getByTestId('time-2026-11-03T18:00:00Z'));
    expect(within(screen.getByTestId('fee-warning')).getByText('This time is less than 1 hour away, so cancelling it may be charged $35.')).toBeTruthy();
  });
});
