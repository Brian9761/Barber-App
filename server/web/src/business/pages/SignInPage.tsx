// Sign in on a computer: the 6-digit code from the iPhone app (Settings → Use on a
// computer), or the owner key instead. The key itself is never kept here: it makes a code,
// and the code buys this computer its own session, which the app lists and can sign out.
// In the demo, one button opens it, with sample data.

import { useRef, useState, type FormEvent } from 'react';
import { isApiError } from '../../api/errors';
import { Icon } from '../../components/Icon';
import { Notice } from '../../components/ui';
import { ownerApi } from '../api/client';
import { APP_NAME, DEMO_LINE, demo, useBusinessTitle } from '../hooks';
import { thisComputerName } from '../lib/computerName';
import { session, useSession } from '../session';

/** The code as typed ("483 920", "483-920") as its 6 digits, or null. */
export function codeDigits(text: string): string | null {
  const digits = text.replace(/[\s-]/g, '');
  return /^\d{6}$/.test(digits) ? digits : null;
}

const WRONG_CODE = "That code isn't right or has run out. Get a new one in the app: Settings → Use on a computer.";

function signInMessage(error: unknown, withKey: boolean): string {
  if (!isApiError(error)) return 'Something went wrong. Try again in a moment.';
  if (error.code === 'wrong_code') return WRONG_CODE;
  if (withKey && (error.code === 'unauthorized' || error.status === 401)) return "That owner key isn't right. Check it and try again.";
  return error.message;
}

function SignedOutLine() {
  const { reason, note } = useSession();
  if (reason === 'expired') {
    return (
      <Notice tone="info" role="status" title="This computer was signed out." testId="signed-out-line">
        <p>
          {demo()
            ? 'Its 30 days ran out. Open the demo again with the button below.'
            : 'It was signed out from the iPhone app, or its 30 days ran out. To sign in again, get a new code in the app.'}
        </p>
      </Notice>
    );
  }
  if (reason === 'signedOut') {
    return (
      <Notice tone="success" role="status" title="You're signed out on this computer." testId="signed-out-line">
        {note ? <p>{note}</p> : null}
      </Notice>
    );
  }
  return null;
}

function Steps() {
  return (
    <ol className="biz-signin__steps" role="list">
      <li>
        <span className="biz-signin__number" aria-hidden="true">
          1
        </span>
        <span>
          Open <strong>Izzy Clipz Business</strong> on your iPhone.
        </span>
      </li>
      <li>
        <span className="biz-signin__number" aria-hidden="true">
          2
        </span>
        <span>
          Tap <strong>Settings</strong> → <strong>Use on a computer</strong>.
        </span>
      </li>
      <li>
        <span className="biz-signin__number" aria-hidden="true">
          3
        </span>
        <span>Type the 6-digit code.</span>
      </li>
    </ol>
  );
}

function CodeForm({ onUseKey }: { onUseKey: () => void }) {
  const [code, setCode] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const input = useRef<HTMLInputElement>(null);
  const submit = async (event: FormEvent) => {
    event.preventDefault();
    const digits = codeDigits(code);
    if (!digits) {
      setError('Type the 6 digits of the code, like 483 920.');
      input.current?.focus();
      return;
    }
    setBusy(true);
    setError(null);
    try {
      session.signIn(await ownerApi.signIn(digits, thisComputerName()));
    } catch (caught) {
      setError(signInMessage(caught, false));
      setBusy(false);
      input.current?.focus();
      input.current?.select();
    }
  };
  return (
    <form className="biz-signin__form" onSubmit={(event) => void submit(event)} noValidate>
      <div className="field">
        <label className="field__label" htmlFor="computer-code">
          6-digit code
        </label>
        <input
          ref={input}
          id="computer-code"
          className="field__input biz-code-input"
          inputMode="numeric"
          autoComplete="one-time-code"
          maxLength={11}
          value={code}
          onChange={(event) => {
            setCode(event.target.value);
            if (error) setError(null);
          }}
          aria-invalid={error ? true : undefined}
          aria-describedby={error ? 'computer-code-error' : 'computer-code-hint'}
          placeholder="000 000"
          spellCheck={false}
        />
        {error ? (
          <p className="field__error" id="computer-code-error" role="alert">
            <Icon name="error" />
            <span>{error}</span>
          </p>
        ) : (
          <p className="field__hint" id="computer-code-hint">
            The code works once, for 10 minutes. Spaces don't matter.
          </p>
        )}
      </div>
      <button type="submit" className="button button--primary button--large button--block" disabled={busy}>
        {busy ? 'Signing in…' : 'Sign in'}
      </button>
      <button type="button" className="text-button biz-signin__switch" onClick={onUseKey}>
        Use the owner key instead
      </button>
    </form>
  );
}

function KeyForm({ onUseCode }: { onUseCode: () => void }) {
  const [key, setKey] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const input = useRef<HTMLInputElement>(null);
  const submit = async (event: FormEvent) => {
    event.preventDefault();
    const trimmed = key.trim();
    if (trimmed === '') {
      setError('Paste or type the owner key.');
      input.current?.focus();
      return;
    }
    setBusy(true);
    setError(null);
    try {
      session.signIn(await ownerApi.signInWithKey(trimmed, thisComputerName()));
    } catch (caught) {
      setError(signInMessage(caught, true));
      setBusy(false);
      input.current?.focus();
    }
  };
  return (
    <form className="biz-signin__form" onSubmit={(event) => void submit(event)} noValidate>
      <div className="field">
        <label className="field__label" htmlFor="owner-key">
          Owner key
        </label>
        <input
          ref={input}
          id="owner-key"
          className="field__input"
          type="password"
          autoComplete="current-password"
          value={key}
          onChange={(event) => {
            setKey(event.target.value);
            if (error) setError(null);
          }}
          aria-invalid={error ? true : undefined}
          aria-describedby={error ? 'owner-key-error' : 'owner-key-hint'}
          spellCheck={false}
        />
        {error ? (
          <p className="field__error" id="owner-key-error" role="alert">
            <Icon name="error" />
            <span>{error}</span>
          </p>
        ) : (
          <p className="field__hint" id="owner-key-hint">
            The key the shop's server was set up with. It isn't kept on this computer.
          </p>
        )}
      </div>
      <button type="submit" className="button button--primary button--large button--block" disabled={busy}>
        {busy ? 'Signing in…' : 'Sign in with the key'}
      </button>
      <button type="button" className="text-button biz-signin__switch" onClick={onUseCode}>
        Use a code from the app instead
      </button>
    </form>
  );
}

function DemoSignIn() {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const open = async () => {
    setBusy(true);
    setError(null);
    try {
      session.signIn(await ownerApi.signIn('', thisComputerName()));
    } catch (caught) {
      setError(signInMessage(caught, false));
      setBusy(false);
    }
  };
  return (
    <div className="biz-signin__demo">
      <p className="demo-notice" data-testid="demo-notice">
        <Icon name="info" className="demo-notice__icon" />
        <span>{DEMO_LINE}</span>
      </p>
      <button type="button" className="button button--primary button--large" onClick={() => void open()} disabled={busy}>
        {busy ? 'Opening…' : 'Open the Business demo'}
      </button>
      {error ? (
        <p className="field__error" role="alert">
          <Icon name="error" />
          <span>{error}</span>
        </p>
      ) : null}
      <p className="secondary small">In the real one, you sign in with a 6-digit code from Izzy Clipz Business on your iPhone: Settings → Use on a computer.</p>
    </div>
  );
}

export function SignInPage() {
  useBusinessTitle(null, 'Izzy Clipz Business on your computer: the shop’s schedule, checkout, sales and analytics.');
  const [withKey, setWithKey] = useState(false);
  return (
    <div className="container biz-signin">
      <SignedOutLine />
      <div className="biz-signin__head">
        <h1>{APP_NAME} on your computer</h1>
        <p className="lead secondary">See the shop's schedule, check clients out, and follow sales and analytics.</p>
      </div>
      {demo() ? (
        <DemoSignIn />
      ) : (
        <div className="biz-signin__card">
          <section className="biz-signin__how" aria-labelledby="signin-how">
            <h2 id="signin-how" className="biz-signin__subtitle">
              Sign in with a code from your iPhone
            </h2>
            <Steps />
          </section>
          <div className="biz-signin__right">
            {withKey ? <KeyForm onUseCode={() => setWithKey(false)} /> : <CodeForm onUseKey={() => setWithKey(true)} />}
            <p className="secondary small biz-signin__fine">
              This computer stays signed in for 30 days, until you sign out. On a shared computer, sign out when you're done.
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
