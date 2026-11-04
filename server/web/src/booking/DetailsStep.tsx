import { useId, useRef, useState, type FormEvent, type ReactNode } from 'react';
import type { Catalog } from '../api/types';
import { Icon } from '../components/Icon';
import { displayPhone, emailProblem, MAX_NOTE_LENGTH, charLength, nameProblem, noteProblem, phoneProblem } from '../lib/phone';
import { forgetDetails, loadCard, loadRememberedDetails, rememberDetails, storeCard } from '../lib/storage';
import { useBooking, useStepNavigation } from './BookingContext';
import type { Details } from './flow';
import { BookingLayout, StepHeader } from './StepChrome';

type FieldName = 'name' | 'phone' | 'email' | 'note';

/**
 * Step 4: who it's for. A name and a US mobile number (so the shop knows who's
 * coming and can reach them), an optional email and note, and "Remember me on
 * this computer". Problems show once the client tries to continue.
 */
export function DetailsStep({ catalog }: { catalog: Catalog }) {
  const { draft, dispatch } = useBooking();
  const { goTo } = useStepNavigation('details');
  const remembered = loadRememberedDetails();
  const initial: Details = draft.details ?? {
    name: remembered?.name ?? '',
    phone: remembered?.phone ?? '',
    email: remembered?.email ?? '',
    note: '',
    remember: true,
  };
  const [values, setValues] = useState<Details>(initial);
  const [showProblems, setShowProblems] = useState(false);
  const refs = { name: useRef<HTMLInputElement>(null), phone: useRef<HTMLInputElement>(null), email: useRef<HTMLInputElement>(null), note: useRef<HTMLTextAreaElement>(null) };
  const ids = { name: useId(), phone: useId(), email: useId(), note: useId() };

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
      // Not remembered: forget the details, and keep a saved card for this visit only.
      forgetDetails();
      const card = loadCard();
      if (card) storeCard(card, false);
    }
    dispatch({ type: 'saveDetails', details });
    goTo('review');
  };

  const problem = (field: FieldName) => (showProblems ? problems[field] : null);

  return (
    <BookingLayout catalog={catalog}>
      <StepHeader step="details" title="Your details" subtitle="So the shop knows who's coming and can reach you if anything changes." />
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
        <Field id={ids.phone} label="Mobile number" problem={problem('phone')} hint="A US number, so the shop can reach you.">
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
        <label className="checkbox">
          <input type="checkbox" checked={values.remember} onChange={(e) => set('remember')(e.target.checked)} />
          <span className="checkbox__text">
            <span className="checkbox__label">Remember me on this computer</span>
            <span className="secondary">Your name and number fill in next time you book here.</span>
          </span>
        </label>
        <p className="secondary">Your name and number are sent only to {catalog.shop.name}, to book and manage this appointment.</p>
        <div className="step-actions">
          <button type="submit" className="button button--primary button--large step-actions__continue">
            Continue
          </button>
        </div>
      </form>
    </BookingLayout>
  );
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
