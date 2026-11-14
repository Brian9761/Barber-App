// What the booking so far says, in the app's words, and what a failed booking
// tells the client (IzzyClipz/Features/Booking/BookingModels.swift).

import { ErrorCode, isApiError, OFFLINE_MESSAGE } from '../api/client';
import type { Appointment, Catalog } from '../api/types';
import { anyBarberOption, barberById, offeringById, serviceById } from '../lib/catalog';
import { durationLabel, list, priceLabel } from '../lib/format';
import { timeLabel } from '../lib/shopTime';
import type { BookingDraft } from './flow';

export interface ChoiceSummary {
  serviceName: string | null;
  /** "Carlos", or "Any barber". */
  barberName: string | null;
  /** "$45", or "$55–$60" for any barber. */
  priceLabel: string | null;
  /** "45 min". */
  durationLabel: string | null;
  /** A barber's note on their version ("Includes mustache & eyebrows…"), or who "Any barber" picks from. */
  barberDetail: string | null;
  isAnyBarber: boolean;
}

export function summarize(catalog: Catalog, draft: Pick<BookingDraft, 'serviceId' | 'choice'>): ChoiceSummary {
  const service = serviceById(catalog, draft.serviceId);
  const summary: ChoiceSummary = {
    serviceName: service?.name ?? null,
    barberName: null,
    priceLabel: null,
    durationLabel: null,
    barberDetail: null,
    isAnyBarber: false,
  };
  if (!draft.choice) return summary;
  if (draft.choice.kind === 'any') {
    const option = draft.serviceId ? anyBarberOption(catalog, draft.serviceId) : null;
    if (!option) return summary;
    return {
      ...summary,
      barberName: 'Any barber',
      priceLabel: option.priceLabel,
      durationLabel: option.durationLabel,
      barberDetail: `The shop books whoever is free first: ${list(option.barbers.map((b) => b.name))}.`,
      isAnyBarber: true,
    };
  }
  const offering = offeringById(catalog, draft.choice.offeringId);
  if (!offering) return summary;
  return {
    ...summary,
    serviceName: serviceById(catalog, offering.serviceId)?.name ?? summary.serviceName,
    barberName: barberById(catalog, offering.barberId)?.name ?? 'Your barber',
    priceLabel: priceLabel(offering),
    durationLabel: durationLabel(offering.durationMinutes),
    barberDetail: offering.note ?? null,
  };
}

/** Why a booking didn't go through, and the way forward the review step offers. */
export type BookingFailure =
  /** The time was taken, or can't be booked any more: back to the times, saying so. */
  | { kind: 'timeGone'; message: string }
  /** The shop couldn't be reached: it may have gone through. Trying again won't book it twice. */
  | { kind: 'offline'; message: string }
  /** A limit, in the server's words (too many tries from this network, or 3 upcoming for this number). */
  | { kind: 'rateLimited'; message: string }
  /** The server turned down the name, number or note: back to the details. */
  | { kind: 'details'; message: string }
  /** The booking needs a card on file, or the one sent can't be used: add one. */
  | { kind: 'card'; message: string }
  /** The no-show policy just changed: show the new one, then book again. */
  | { kind: 'policy'; message: string }
  | { kind: 'other'; message: string };

export function failureTitle(failure: BookingFailure): string {
  return failure.kind === 'offline' ? 'Not confirmed yet' : 'Not booked yet';
}

/** The app's words for each answer, with the picked time in them. */
export function bookingFailure(error: unknown, start: Date, zone: string): BookingFailure {
  const time = timeLabel(start, zone);
  if (!isApiError(error)) return { kind: 'other', message: 'Something went wrong on our side. Try again in a moment, or call the shop.' };
  switch (error.code) {
    case ErrorCode.slotTaken:
      return { kind: 'timeGone', message: `Someone just booked ${time}. Pick another time.` };
    case ErrorCode.tooSoon:
      return { kind: 'timeGone', message: `${time} is too soon to book now. Pick a later time.` };
    case ErrorCode.outsideHours:
      return { kind: 'timeGone', message: `${time} is outside the shop's hours. Pick another time.` };
    case ErrorCode.tooFar:
      return { kind: 'timeGone', message: 'That day is too far ahead to book. Pick an earlier day.' };
    case ErrorCode.rateLimited:
      return { kind: 'rateLimited', message: error.message };
    case ErrorCode.cardRequired:
      return { kind: 'card', message: error.message };
    case ErrorCode.policyChanged:
      return { kind: 'policy', message: error.message };
    case ErrorCode.invalidRequest:
      return { kind: 'details', message: error.message.trim() || 'Check your name and number, then try again.' };
    default:
      return error.isOffline ? { kind: 'offline', message: OFFLINE_MESSAGE } : { kind: 'other', message: error.message };
  }
}

/** A retry found the booking an earlier try made, but it isn't on any more. */
export function noLongerBooked(appointment: Appointment, zone: string): string {
  const time = timeLabel(new Date(appointment.start), zone);
  if (appointment.status === 'cancelled' && appointment.cancelledBy === 'shop') {
    return `Your booking for ${time} went through, but the shop has cancelled it since. Pick another time, or call the shop.`;
  }
  return `Your booking for ${time} went through, but it isn't on any more. Pick another time, or call the shop.`;
}
