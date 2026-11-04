// "Add to calendar": an .ics file (RFC 5545) for an appointment, with the shop's
// address, which every calendar app opens (Apple Calendar, Outlook, Google).

import type { Appointment, Shop } from '../api/types';
import { durationLabel } from './format';

export interface CalendarEvent {
  uid: string;
  start: Date;
  end: Date;
  title: string;
  location: string;
  description: string;
  url?: string;
  geo?: { latitude: number; longitude: number };
  /** Minutes before the start for a reminder; none without. */
  alarmMinutes?: number;
}

/** 20261105T183000Z */
export function icsTime(date: Date): string {
  return date.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
}

/** Text with RFC 5545's escapes: backslash, semicolon, comma and line breaks. */
export function escapeText(text: string): string {
  return text.replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\r?\n/g, '\\n');
}

/** Folds a content line at 75 octets (UTF-8), continuing with a space, never inside a character. */
export function foldLine(line: string): string {
  const encoder = new TextEncoder();
  const parts: string[] = [];
  let current = '';
  let size = 0;
  for (const char of line) {
    const bytes = encoder.encode(char).length;
    const limit = parts.length === 0 ? 75 : 74;
    if (size + bytes > limit) {
      parts.push(current);
      current = '';
      size = 0;
    }
    current += char;
    size += bytes;
  }
  parts.push(current);
  return parts.join('\r\n ');
}

export function icsFile(event: CalendarEvent, now: Date = new Date()): string {
  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Izzy Clipz//Website//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    `UID:${event.uid}`,
    `DTSTAMP:${icsTime(now)}`,
    `DTSTART:${icsTime(event.start)}`,
    `DTEND:${icsTime(event.end)}`,
    `SUMMARY:${escapeText(event.title)}`,
    `LOCATION:${escapeText(event.location)}`,
    `DESCRIPTION:${escapeText(event.description)}`,
    ...(event.geo ? [`GEO:${event.geo.latitude};${event.geo.longitude}`] : []),
    ...(event.url ? [`URL:${event.url}`] : []),
    ...(event.alarmMinutes
      ? ['BEGIN:VALARM', 'ACTION:DISPLAY', `DESCRIPTION:${escapeText(event.title)}`, `TRIGGER:-PT${event.alarmMinutes}M`, 'END:VALARM']
      : []),
    'END:VEVENT',
    'END:VCALENDAR',
  ];
  return `${lines.map(foldLine).join('\r\n')}\r\n`;
}

/** The event for an appointment at the shop, as the app's Add to Calendar words it. */
export function appointmentEvent(appointment: Appointment, shop: Shop, siteOrigin: string): CalendarEvent {
  const barber = appointment.barberName;
  return {
    uid: `${appointment.id}@izzyclipz`,
    start: new Date(appointment.start),
    end: new Date(appointment.end),
    title: `${appointment.serviceName} at ${shop.name}`,
    location: `${shop.fullName}, ${shop.address.lines.join(', ')}`,
    description: [
      `${appointment.serviceName} with ${barber}`,
      `${appointment.priceLabel} · ${durationLabel(appointment.durationMinutes)} · Pay at the shop`,
      `To change or cancel, go to ${siteOrigin}/appointments or call ${shop.phone.display}.`,
    ].join('\n'),
    url: `${siteOrigin}/appointments`,
    geo: shop.coordinate,
    alarmMinutes: 60,
  };
}

/** Hands the file to the browser to save or open. */
export function downloadIcs(fileName: string, contents: string): void {
  const blob = new Blob([contents], { type: 'text/calendar;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = fileName;
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
}
