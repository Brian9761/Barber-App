import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import cardSaved from '../../../test/fixtures/contract/card-saved.json';
import { CARD_KEY, loadCard, loadRememberedDetails, rememberDetails, storeCard } from '../lib/storage';
import { newToken } from '../lib/tokens';
import { FLOW45, mockApi, policy35, renderApp } from '../test/api';
import { USER_AGENTS } from '../test/pwa';
import { EMPTY_DRAFT, loadDraft, saveDraft } from './flow';

// "Remember me on this computer": a computer can be shared, so it starts off for anyone
// it doesn't already remember, and a saved card only ever goes to the number that added it.

const ALEX = { name: 'Alex Ames', phone: '(760) 555-0161', email: '' };
const ALEX_E164 = '+17605550161';
const ANA_E164 = '+14425550123';

/** A booking taken to the details step: Flowxbori's haircut at 10 AM on Tuesday, November 3. */
function atDetails() {
  saveDraft({ ...EMPTY_DRAFT, serviceId: 'haircut', choice: { kind: 'offering', offeringId: FLOW45 }, start: '2026-11-03T18:00:00Z' });
  mockApi([['GET /api/no-show-policy', { body: policy35 }]]);
  renderApp('/book/details');
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
    storeCard({ token: newToken(), card: cardSaved.card, phone: ALEX_E164 }, true);
    atDetails();

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
    expect(screen.getByRole('status').textContent).toBe('Done. This computer no longer keeps those details or a saved card.');
    // Gone from this computer: the name and number, and the card.
    expect(loadRememberedDetails()).toBeNull();
    expect(loadCard()).toBeNull();
    expect(screen.queryByTestId('remembered-note')).toBeNull();
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
    storeCard({ token: newToken(), card: cardSaved.card, phone: ALEX_E164 }, true);
    atDetails();

    await screen.findByRole('heading', { level: 1, name: 'Your details' });
    await type('Name', 'Ana Flores');
    await type('Mobile number', '4425550123');
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }));
    await screen.findByRole('heading', { level: 1, name: 'Review and book' });

    // Alex's card is forgotten, and Review asks Ana for her own.
    expect(loadCard()).toBeNull();
    const section = await screen.findByTestId('card-section');
    expect(within(section).queryByTestId('card-label')).toBeNull();
    expect(within(section).getByRole('button', { name: 'Add a card' })).toBeTruthy();
  });
});
