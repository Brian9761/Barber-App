import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import cardDeleted from '../../../test/fixtures/contract/card-deletion.json';
import cardScheduled from '../../../test/fixtures/contract/card-deletion-scheduled.json';
import cardSaved from '../../../test/fixtures/contract/card-saved.json';
import { CARD_KEY, loadCard, loadRememberedDetails, rememberDetails, storeCard } from '../lib/storage';
import { newToken } from '../lib/tokens';
import { apiError, FLOW45, mockApi, policy35, renderApp } from '../test/api';
import { USER_AGENTS } from '../test/pwa';
import { visibleText } from '../test/text';
import { EMPTY_DRAFT, loadDraft, saveDraft } from './flow';

// "Remember me on this computer": a computer can be shared, so it starts off for anyone
// it doesn't already remember, and a saved card only ever goes to the number that added it.

const ALEX = { name: 'Alex Ames', phone: '(760) 555-0161', email: '' };
const ALEX_E164 = '+17605550161';
const ANA_E164 = '+14425550123';

/** A booking taken to the details step: Flowxbori's haircut at 10 AM on Tuesday, November 3. */
function atDetails(routes: Parameters<typeof mockApi>[0] = []) {
  saveDraft({ ...EMPTY_DRAFT, serviceId: 'haircut', choice: { kind: 'offering', offeringId: FLOW45 }, start: '2026-11-03T18:00:00Z' });
  const api = mockApi([['GET /api/no-show-policy', { body: policy35 }], ...routes]);
  renderApp('/book/details');
  return api;
}

const field = (label: string) => screen.getByLabelText(label) as HTMLInputElement;
const rememberBox = () => screen.getByRole('checkbox', { name: 'Remember me on this computer' }) as HTMLInputElement;

async function type(label: string, text: string) {
  await userEvent.clear(field(label));
  await userEvent.type(field(label), text);
}

describe('Remember me on this computer', () => {
  it('starts off for someone this computer doesn’t know, and says what it keeps', async () => {
    atDetails();
    await screen.findByRole('heading', { level: 1, name: 'Your details' });
    expect(rememberBox().checked).toBe(false);
    expect(field('Name').value).toBe('');
    expect(screen.getByText(/a card you add stays saved\. Leave it off on a shared computer\./)).toBeTruthy();
    expect(screen.queryByTestId('remembered-note')).toBeNull();
    // The real site sends the details to the shop, and says so (the demo says they stay here).
    expect(screen.getByText("So the shop knows who's coming and can reach you if anything changes.")).toBeTruthy();
    // Who gets them, as the Privacy Policy says, which opens in a new tab so the booking stays.
    const privacy = screen.getByTestId('details-privacy');
    expect(visibleText(privacy)).toBe('Your details go to Izzy Clipz Barbershop and the services that run its booking, as our Privacy Policy explains.');
    const link = within(privacy).getByRole('link', { name: /^Privacy Policy\s*\(opens in a new tab\)$/ });
    expect([link.getAttribute('href'), link.getAttribute('target')]).toEqual(['/privacy', '_blank']);
  });

  it('names the device it’s on: on a phone, this phone', async () => {
    vi.spyOn(navigator, 'userAgent', 'get').mockReturnValue(USER_AGENTS.iphoneSafari);
    rememberDetails(ALEX);
    atDetails();
    await screen.findByRole('heading', { level: 1, name: 'Your details' });
    expect(screen.getByRole('checkbox', { name: 'Remember me on this phone' })).toBeTruthy();
    expect(screen.getByText(/a card you add stays saved\. Leave it off on a shared phone\./)).toBeTruthy();
    expect(screen.getByTestId('remembered-note').textContent).toContain('Your details are filled in from this phone.');
    await userEvent.click(screen.getByRole('button', { name: 'Not you? Forget me on this phone' }));
    expect(screen.getByText('Done. This phone no longer keeps those details or a saved card.')).toBeTruthy();
  });

  it('remembers nothing when left off', async () => {
    atDetails();
    await type('Name', 'Ana Flores');
    await type('Mobile number', '4425550123');
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }));
    await screen.findByRole('heading', { level: 1, name: 'Review and book' });
    expect(loadRememberedDetails()).toBeNull();
    expect(loadDraft()?.details).toMatchObject({ name: 'Ana Flores', remember: false });
  });

  it('fills in the client it remembers, still on, with “Not you? Forget me on this computer”', async () => {
    rememberDetails(ALEX);
    const token = newToken();
    storeCard({ token, card: cardSaved.card, phone: ALEX_E164 }, true);
    const api = atDetails([['DELETE /api/cards', { body: cardScheduled }]]);

    await screen.findByRole('heading', { level: 1, name: 'Your details' });
    expect(field('Name').value).toBe('Alex Ames');
    expect(field('Mobile number').value).toBe('(760) 555-0161');
    expect(rememberBox().checked).toBe(true);
    const note = screen.getByTestId('remembered-note');
    expect(note.textContent).toContain('Welcome back, Alex.');

    await userEvent.click(within(note).getByRole('button', { name: 'Not you? Forget me on this computer' }));
    expect(field('Name').value).toBe('');
    expect(field('Mobile number').value).toBe('');
    expect(rememberBox().checked).toBe(false);
    expect(document.activeElement).toBe(field('Name'));
    // Gone from this computer at once: the name and number, and the card.
    expect(loadRememberedDetails()).toBeNull();
    expect(loadCard()).toBeNull();
    expect(screen.queryByTestId('remembered-note')).toBeNull();
    // And the shop deletes the card once Alex's appointments no longer need it, in one plain line.
    await waitFor(() =>
      expect(screen.getByRole('status').textContent).toBe(
        'Done. This computer no longer keeps those details or a saved card. The shop will delete the saved card as soon as the appointments booked with it no longer need it.',
      ),
    );
    expect(api.calls.filter((c) => c.method === 'DELETE')).toMatchObject([{ path: '/api/cards', headers: { 'x-card-token': token }, keepalive: true }]);
  });

  it('says the shop deleted the card, or to call the shop when it couldn’t be reached; forgets it here either way', async () => {
    rememberDetails(ALEX);
    storeCard({ token: newToken(), card: cardSaved.card, phone: ALEX_E164 }, true);
    atDetails([['DELETE /api/cards', { body: cardDeleted }]]);
    await userEvent.click(await screen.findByRole('button', { name: 'Not you? Forget me on this computer' }));
    expect(await screen.findByText("The shop deleted the saved card too, so it can't be charged any more.")).toBeTruthy();
  });

  it('forgets the card here when the shop can’t be reached, and says to call the shop', async () => {
    rememberDetails(ALEX);
    storeCard({ token: newToken(), card: cardSaved.card, phone: ALEX_E164 }, true);
    atDetails([['DELETE /api/cards', 'offline']]);
    await userEvent.click(await screen.findByRole('button', { name: 'Not you? Forget me on this computer' }));
    expect(loadCard()).toBeNull();
    expect(
      await screen.findByText("The shop couldn't be reached to delete the saved card. To have it removed, call the shop at (442) 341-3053."),
    ).toBeTruthy();
  });

  it('says nothing more about the card when the shop had none under that key', async () => {
    rememberDetails(ALEX);
    storeCard({ token: newToken(), card: cardSaved.card, phone: ALEX_E164 }, true);
    const api = atDetails([['DELETE /api/cards', apiError('not_found', "We couldn't find that card.", 404)]]);
    await userEvent.click(await screen.findByRole('button', { name: 'Not you? Forget me on this computer' }));
    await waitFor(() => expect(api.calls.some((c) => c.method === 'DELETE')).toBe(true));
    await waitFor(() => expect(screen.getByRole('status').textContent).toBe('Done. This computer no longer keeps those details or a saved card.'));
  });

  it('turned off by the client it remembers: forgets them, and keeps their card for this visit only', async () => {
    const token = newToken();
    rememberDetails({ name: 'Ana Flores', phone: '(442) 555-0123', email: '' });
    storeCard({ token, card: cardSaved.card, phone: ANA_E164 }, true);
    atDetails();

    await screen.findByRole('heading', { level: 1, name: 'Your details' });
    await userEvent.click(rememberBox());
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }));
    await screen.findByRole('heading', { level: 1, name: 'Review and book' });

    expect(loadRememberedDetails()).toBeNull();
    expect(localStorage.getItem(CARD_KEY)).toBeNull();
    expect(JSON.parse(sessionStorage.getItem(CARD_KEY)!)).toEqual({ token, card: cardSaved.card, phone: ANA_E164 });
    // Her own card holds this booking.
    expect((await screen.findByTestId('card-label')).textContent).toContain('Visa •••• 4242');
  });

  it('never hands someone else’s card to the next client', async () => {
    // Alex asked to be remembered on this computer; Ana types her own name and number over his.
    rememberDetails(ALEX);
    const alexCard = newToken();
    storeCard({ token: alexCard, card: cardSaved.card, phone: ALEX_E164 }, true);
    const api = atDetails([['DELETE /api/cards', { body: cardScheduled }]]);

    await screen.findByRole('heading', { level: 1, name: 'Your details' });
    await type('Name', 'Ana Flores');
    await type('Mobile number', '4425550123');
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }));
    await screen.findByRole('heading', { level: 1, name: 'Review and book' });

    // Alex's card is forgotten, and Review asks Ana for her own. Nobody could use Alex's card from
    // here again, so the shop is asked to delete it.
    expect(loadCard()).toBeNull();
    const section = await screen.findByTestId('card-section');
    expect(within(section).queryByTestId('card-label')).toBeNull();
    expect(within(section).getByRole('button', { name: 'Add a card' })).toBeTruthy();
    await waitFor(() => expect(api.calls.filter((c) => c.method === 'DELETE')).toMatchObject([{ headers: { 'x-card-token': alexCard } }]));
  });

  it('asks the shop nothing when the client keeps their own card', async () => {
    rememberDetails({ name: 'Ana Flores', phone: '(442) 555-0123', email: '' });
    storeCard({ token: newToken(), card: cardSaved.card, phone: ANA_E164 }, true);
    const api = atDetails();
    await screen.findByRole('heading', { level: 1, name: 'Your details' });
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }));
    await screen.findByRole('heading', { level: 1, name: 'Review and book' });
    expect(api.calls.filter((c) => c.method === 'DELETE')).toEqual([]);
  });
});
