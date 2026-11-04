import { describe, expect, it } from 'vitest';
import { catalog, fixtureAppointment } from '../test/api';
import { appointmentEvent, escapeText, foldLine, icsFile, icsTime } from './ics';

const ORIGIN = 'https://izzyclipz.example';
const file = () => icsFile(appointmentEvent(fixtureAppointment, catalog.shop, ORIGIN), new Date('2026-11-02T17:00:05.123Z'));
/** The file's lines with folding undone, as a calendar reads them. */
const unfolded = (ics: string) => ics.replace(/\r\n /g, '').split('\r\n');

describe('Add to calendar', () => {
  it('is one event at the shop, at the booked time, with a reminder an hour before', () => {
    const lines = unfolded(file());
    expect(lines.slice(0, 6)).toEqual(['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Izzy Clipz//Website//EN', 'CALSCALE:GREGORIAN', 'METHOD:PUBLISH', 'BEGIN:VEVENT']);
    expect(lines).toContain('UID:00000000-0000-4000-8000-000000000005@izzyclipz');
    expect(lines).toContain('DTSTAMP:20261102T170005Z');
    expect(lines).toContain('DTSTART:20261103T180000Z');
    expect(lines).toContain('DTEND:20261103T184500Z');
    expect(lines).toContain('SUMMARY:Haircut at Izzy Clipz');
    expect(lines).toContain(`LOCATION:Izzy Clipz Barbershop\\, ${catalog.shop.address.lines.map(escapeText).join('\\, ')}`);
    expect(lines).toContain(
      `DESCRIPTION:Haircut with Flowxbori\\n$35 · 45 min · Pay at the shop\\nTo change or cancel\\, go to ${ORIGIN}/appointments or call ${catalog.shop.phone.display}.`,
    );
    expect(lines).toContain(`GEO:${catalog.shop.coordinate.latitude};${catalog.shop.coordinate.longitude}`);
    expect(lines).toContain(`URL:${ORIGIN}/appointments`);
    expect(lines).toContain('TRIGGER:-PT60M');
    expect(lines.filter((l) => l === 'BEGIN:VEVENT')).toHaveLength(1);
    expect(lines.slice(-3)).toEqual(['END:VEVENT', 'END:VCALENDAR', '']);
  });

  it('in the demo, says the shop doesn’t have it, and sets no reminder', () => {
    const lines = unfolded(icsFile(appointmentEvent(fixtureAppointment, catalog.shop, ORIGIN, { demo: true }), new Date('2026-11-02T17:00:05.123Z')));
    expect(lines).toContain('SUMMARY:DEMO\\, not booked: Haircut at Izzy Clipz');
    expect(lines).toContain(
      `DESCRIPTION:Demo version: this booking wasn't sent to the shop\\, and Izzy Clipz doesn't have it. To book for real\\, call ${catalog.shop.phone.display}.\\nHaircut with Flowxbori\\n$35 · 45 min · Pay at the shop`,
    );
    expect(lines.some((line) => line.startsWith('BEGIN:VALARM') || line.startsWith('TRIGGER'))).toBe(false);
    // The rest is as on the real site: the time and the place.
    expect(lines).toContain('DTSTART:20261103T180000Z');
    expect(lines.some((line) => line.startsWith('LOCATION:Izzy Clipz Barbershop'))).toBe(true);
  });

  it('follows RFC 5545: CRLF line ends and lines of at most 75 octets', () => {
    const ics = file();
    expect(ics.endsWith('\r\n')).toBe(true);
    expect(ics.replace(/\r\n/g, '')).not.toMatch(/[\r\n]/);
    const encoder = new TextEncoder();
    for (const line of ics.split('\r\n')) expect(encoder.encode(line).length).toBeLessThanOrEqual(75);
  });

  it('writes times in UTC and escapes text', () => {
    expect(icsTime(new Date('2026-03-08T17:00:00.000Z'))).toBe('20260308T170000Z');
    expect(escapeText('Fade; low, please\\ thanks\nsee you')).toBe('Fade\\; low\\, please\\\\ thanks\\nsee you');
  });

  it('folds long lines without splitting a character', () => {
    const line = `DESCRIPTION:${'💈'.repeat(30)}`;
    const folded = foldLine(line);
    expect(folded.replace(/\r\n /g, '')).toBe(line);
    for (const part of folded.split('\r\n')) expect(new TextEncoder().encode(part).length).toBeLessThanOrEqual(75);
    expect(foldLine('SUMMARY:Haircut')).toBe('SUMMARY:Haircut');
  });
});
