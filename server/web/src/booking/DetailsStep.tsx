import { useId, useRef, useState, type FormEvent, type ReactNode } from 'react';
import type { Catalog } from '../api/types';
import { Icon } from '../components/Icon';
import { isDemo } from '../demo/mode';
import { displayPhone, emailProblem, MAX_NOTE_LENGTH, charLength, nameProblem, noteProblem, parseUSPhone, phoneProblem, toE164 } from '../lib/phone';
import { forgetClient, forgetDetails, keepCardFor, loadRememberedDetails, rememberDetails } from '../lib/storage';
import { thisDevice } from '../pwa/platform';
import { useBooking, useStepNavigation } from './BookingContext';
import type { Details } from './flow';
import { BookingLayout, StepHeader } from './StepChrome';

type FieldName = 'name' | 'phone' | 'email' | 'note';

const EMPTY_DETAILS: Details = { name: '', phone: '', email: '', note: '', remember: false };

/**
 * Step 4: who it's for. A name and a US mobile number (so the shop knows who's
 * coming and can reach them), an optional email and note, and "Remember me on
 * this phone" (or computer, iPad, tablet). Problems show once the client tries
 * to continue.
 *
 * A computer can be shared, so "Remember me" starts off, unless this computer
 * already remembers the client (they ticked it last time); then "Not you? Forget
 * me on this computer" clears it for whoever is booking now.
 *
 * In the demo nothing reaches the shop, so the step says the details stay on this
 * device, and "Remember me" says nothing of a saved card (the demo never asks for one).
 */
export function DetailsStep({ catalog }: { catalog: Catalog }) {
  const device = thisDevice();
  const demo = isDemo();
  const { draft, dispatch } = useBooking();
  const { goTo } = useStepNavigation('details');
  const [remembered, setRemembered] = useState(() => loadRememberedDetails());
  const [values, setValues] = useState<Details>(
    () =>
      draft.details ??
      (remembered ? { name: remembered.name, phone: remembered.phone, email: remembered.email, note: '', remember: true } : EMPTY_DETAILS),
  );
  const [showProblems, setShowProblems] = useState(false);
  const [forgotten, setForgotten] = useState(false);
  const refs = { name: useRef<HTMLInputElement>(null), phone: useRef<HTMLInputElement>(null), email: useRef<HTMLInputElement>(null), note: useRef<HTMLTextAreaElement>(null) };
  const ids = { name: useId(), phone: useId(), email: useId(), note: useId(), remember: useId() };

  const problems: Record<FieldName, string | null> = {
    name: nameProblem(values.name),
    phone: phoneProblem(values.phone),
    email: emailProblem(values.email),
    note: noteProblem(values.note),
  };

  const set = (field: keyof Details) => (value: string | boolean) => setValues((v) => ({ ...v, [field]: value }));

  const submit = (event: FormEvent) => {
    event.preventDefault();
    const firstProblem = (['name', 'phone', 'email', 'note'] as const).find((f) => problems[f]);
    if (firstProblem) {
      setShowProblems(true);
      refs[firstProblem].current?.focus();
      return;
    }
    const details: Details = {
      name: values.name.trim(),
      phone: displayPhone(values.phone),
      email: values.email.trim(),
      note: values.note.trim(),
      remember: values.remember,
    };
    if (details.remember) {
      rememberDetails({ name: details.name, phone: details.phone, email: details.email });
    } else {
      forgetDetails();
    }
    // A card saved on this computer goes with the same choice (kept for next time, or for
    // this visit only), and only for the client who added it: anyone else's is forgotten.
    keepCardFor(toE164(parseUSPhone(details.phone)!), details.remember);
    dispatch({ type: 'saveDetails', details });
    goTo('review');
  };

  /** Someone else is booking: this computer forgets the remembered client, and the form starts empty. */
  const forgetMe = () => {
    forgetClient();
    dispatch({ type: 'forgetDetails' });
    setRemembered(null);
    setValues(EMPTY_DETAILS);
    setShowProblems(false);
    setForgotten(true);
    refs.name.current?.focus();
  };

  const problem = (field: FieldName) => (showProblems ? problems[field] : null);

  return (
    <BookingLayout catalog={catalog}>
      <StepHeader
        step="details"
        title="Your details"
        subtitle={
          demo
            ? `This is the demo: your details stay on this ${device} and aren't sent anywhere.`
            : "So the shop knows who's coming and can reach you if anything changes."
        }
      />
      {remembered ? (
        <p className="remembered-note" data-testid="remembered-note">
          <span>
            Welcome back, {firstName(remembered.name)}. Your details are filled in from this {device}.
          </span>{' '}
          <button type="button" className="text-button" onClick={forgetMe}>
            Not you? Forget me on this {device}
          </button>
        </p>
      ) : null}
      {forgotten ? (
        <p className="remembered-note" role="status">
          {/* The demo never keeps a card. */}
          {demo ? `Done. This ${device} no longer keeps those details.` : `Done. This ${device} no longer keeps those details or a saved card.`}
        </p>
      ) : null}
      <form className="form details-form" noValidate onSubmit={submit}>
        <Field id={ids.name} label="Name" problem={problem('name')}>
          <input
            ref={refs.name}
            id={ids.name}
            className="field__input"
            type="text"
            autoComplete="name"
            autoCapitalize="words"
            spellCheck={false}
            placeholder="First and last name"
            value={values.name}
            onChange={(e) => set('name')(e.target.value)}
            aria-invalid={problem('name') ? true : undefined}
            aria-describedby={problem('name') ? `${ids.name}-problem` : undefined}
          />
        </Field>
        <Field
          id={ids.phone}
          label="Mobile number"
          problem={problem('phone')}
          // In the demo nothing reaches the shop, so it can't reach anyone either.
          hint={demo ? 'A US number, like (442) 555-0123.' : 'A US number, so the shop can reach you.'}
        >
          <input
            ref={refs.phone}
            id={ids.phone}
            className="field__input"
            type="tel"
            inputMode="tel"
            autoComplete="tel-national"
            placeholder="(442) 555-0123"
            value={values.phone}
            onChange={(e) => set('phone')(e.target.value)}
            aria-invalid={problem('phone') ? true : undefined}
            aria-describedby={`${ids.phone}-hint${problem('phone') ? ` ${ids.phone}-problem` : ''}`}
          />
        </Field>
        <Field id={ids.email} label="Email" optional problem={problem('email')}>
          <input
            ref={refs.email}
            id={ids.email}
            className="field__input"
            type="email"
            autoComplete="email"
            placeholder="name@example.com"
            value={values.email}
            onChange={(e) => set('email')(e.target.value)}
            aria-invalid={problem('email') ? true : undefined}
            aria-describedby={problem('email') ? `${ids.email}-problem` : undefined}
          />
        </Field>
        <Field id={ids.note} label="Note for your barber" optional problem={problem('note')} hint={`${charLength(values.note)} of ${MAX_NOTE_LENGTH} characters`}>
          <textarea
            ref={refs.note}
            id={ids.note}
            className="field__input"
            rows={3}
            maxLength={MAX_NOTE_LENGTH}
            placeholder="For example, a fade with a beard trim"
            value={values.note}
            onChange={(e) => set('note')(e.target.value)}
            aria-invalid={problem('note') ? true : undefined}
            aria-describedby={`${ids.note}-hint${problem('note') ? ` ${ids.note}-problem` : ''}`}
          />
        </Field>
        <div className="checkbox">
          <input
            id={ids.remember}
            type="checkbox"
            checked={values.remember}
            onChange={(e) => set('remember')(e.target.checked)}
            aria-describedby={`${ids.remember}-hint`}
          />
          <span className="checkbox__text">
            {/* The label covers the whole box, so a click anywhere on it ticks the box. */}
            <label className="checkbox__label" htmlFor={ids.remember}>
              Remember me on this {device}
            </label>
            <span id={`${ids.remember}-hint`} className="secondary">
              {demo
                ? `Your name and number fill in next time you book here. Leave it off on a shared ${device}.`
                : `Your name and number fill in next time you book here, and a card you add stays saved. Leave it off on a shared ${device}.`}
            </span>
          </span>
        </div>
        <p className="secondary" data-testid="details-privacy">
          {demo
            ? `Demo version: your name and number stay on this ${device}. Nothing is sent to ${catalog.shop.name} or anywhere else.`
            : `Your name and number are sent only to ${catalog.shop.name}, to book and manage this appointment.`}
        </p>
        <div className="step-actions">
          <button type="submit" className="button button--primary button--large step-actions__continue">
            Continue
          </button>
        </div>
      </form>
    </BookingLayout>
  );
}

/** "Ana" from "Ana Flores". */
function firstName(name: string): string {
  return name.trim().split(/\s+/)[0] ?? name;
}

function Field({
  id,
  label,
  optional = false,
  hint,
  problem,
  children,
}: {
  id: string;
  label: string;
  optional?: boolean;
  hint?: string;
  problem: string | null;
  children: ReactNode;
}) {
  return (
    <div className="field">
      <label className="field__label" htmlFor={id}>
        {label}
        {optional ? <span className="field__optional"> (optional)</span> : null}
      </label>
      {children}
      {hint ? (
        <p id={`${id}-hint`} className="field__hint">
          {hint}
        </p>
      ) : null}
      {problem ? (
        <p id={`${id}-problem`} className="field__error" role="alert">
          <Icon name="error" />
          {problem}
        </p>
      ) : null}
    </div>
  );
}
