import { describe, expect, it } from 'vitest';
import cardDeleted from '../../../test/fixtures/contract/card-deletion.json';
import cardScheduled from '../../../test/fixtures/contract/card-deletion-scheduled.json';
import { apiError, mockApi } from '../test/api';
import { deleteSavedCard, forgetMeCardLine, notYouCardLine } from './cardRemoval';
import { newToken } from './tokens';

const PHONE = '(442) 341-3053';

describe('deleting a saved card at the shop', () => {
  it('gives back what the shop did: deleted now, or once no booking needs it', async () => {
    const token = newToken();
    const mock = mockApi([['DELETE /api/cards', { body: cardDeleted }]]);
    expect(await deleteSavedCard(token)).toEqual({ status: 'deleted', message: cardDeleted.cardDeletion.message });
    mock.once('DELETE /api/cards', { body: cardScheduled });
    expect(await deleteSavedCard(token)).toEqual({ status: 'scheduled', message: cardScheduled.cardDeletion.message });
    expect(mock.calls.map((c) => [c.method, c.path, c.headers['x-card-token']])).toEqual([
      ['DELETE', '/api/cards', token],
      ['DELETE', '/api/cards', token],
    ]);
    // Sent so it still goes if the client closes the tab right after: the key is gone from here.
    expect(mock.calls.map((c) => c.keepalive)).toEqual([true, true]);
  });

  it('says there was nothing to delete when the shop has no card with that key', async () => {
    mockApi([['DELETE /api/cards', apiError('not_found', "We couldn't find that card.", 404)]]);
    expect(await deleteSavedCard(newToken())).toEqual({ status: 'none' });
  });

  it('tries once more when the connection drops, and never throws', async () => {
    const mock = mockApi([['DELETE /api/cards', { body: cardScheduled }]]);
    mock.once('DELETE /api/cards', 'offline');
    expect(await deleteSavedCard(newToken(), { keepalive: true })).toMatchObject({ status: 'scheduled' });
    expect(mock.calls.map((c) => c.keepalive)).toEqual([true, true]);

    const down = mockApi([['DELETE /api/cards', 'offline']]);
    expect(await deleteSavedCard(newToken())).toEqual({ status: 'failed' });
    expect(down.calls).toHaveLength(2);

    const broken = mockApi([['DELETE /api/cards', apiError('server_error', 'Something went wrong.', 500)]]);
    expect(await deleteSavedCard(newToken())).toEqual({ status: 'failed' });
    expect(broken.calls).toHaveLength(1);
  });
});

describe('what the site says about it', () => {
  it('on My appointments ("Forget me"): the shop’s own words, or to call the shop', () => {
    expect(forgetMeCardLine(null, PHONE)).toBeNull();
    expect(forgetMeCardLine({ status: 'asking' }, PHONE)).toBe('Asking the shop to delete your saved card…');
    expect(forgetMeCardLine(cardDeleted.cardDeletion as never, PHONE)).toBe("Your saved card is deleted. It can't be charged any more.");
    expect(forgetMeCardLine(cardScheduled.cardDeletion as never, PHONE)).toBe('Your card will be deleted as soon as your appointments no longer need it.');
    expect(forgetMeCardLine({ status: 'none' }, PHONE)).toBeNull();
    expect(forgetMeCardLine({ status: 'failed' }, PHONE)).toBe(
      "We couldn't reach the shop to delete your saved card. To have it removed, call the shop at (442) 341-3053.",
    );
  });

  it('on Your details ("Not you?"), for whoever tapped it', () => {
    expect(notYouCardLine(cardDeleted.cardDeletion as never, PHONE)).toBe("The shop deleted the saved card too, so it can't be charged any more.");
    expect(notYouCardLine(cardScheduled.cardDeletion as never, PHONE)).toBe(
      'The shop will delete the saved card as soon as the appointments booked with it no longer need it.',
    );
    expect(notYouCardLine({ status: 'failed' }, PHONE)).toBe(
      "The shop couldn't be reached to delete the saved card. To have it removed, call the shop at (442) 341-3053.",
    );
    expect(notYouCardLine({ status: 'none' }, PHONE)).toBeNull();
  });
});
