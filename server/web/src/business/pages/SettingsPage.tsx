// Settings: Card payments (Stripe), with the status as the app shows it and Connect Stripe
// or Finish setting up, which opens Stripe's own page and comes back here; No-show
// protection, the same settings as the app; this computer, and the other computers signed
// in; how to put Izzy Clipz Business on this phone or computer; and in the demo, Reset.

import { useEffect, useRef, useState, type ReactNode } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { errorMessage } from '../../api/errors';
import { Dialog } from '../../components/Dialog';
import { Icon } from '../../components/Icon';
import { Notice } from '../../components/ui';
import { useCatalog } from '../../data/catalog';
import { windowLabel } from '../../lib/format';
import { leaveTo } from '../../lib/leave';
import { dateTimeLabel } from '../../lib/shopTime';
import type { AppIdentity } from '../../pwa/drawings';
import { promptInstall, useInstallPrompt } from '../../pwa/installPrompt';
import { AndroidSteps, ComputerSteps, DevicePicker, InstallNow, IPhoneSteps } from '../../pwa/InstallSteps';
import { currentPlatform, useStandalone, type Device } from '../../pwa/platform';
import { ownerApi } from '../api/client';
import { ErrorBanner, PageHeader, SkeletonCard, SuccessLine } from '../components/common';
import { useSignOut } from '../components/Frame';
import { APP_NAME, demo, useBusinessTitle, useLoad } from '../hooks';
import * as noShow from '../lib/noShow';
import { stripeReturnLine, stripeView } from '../lib/stripe';
import { session, useSession } from '../session';
import type { ComputerSession, NoShowSettings, StripeConnection } from '../types';

/** Izzy Clipz Business, called "IC Business" under its icon on a Home Screen (business/index.html's apple-mobile-web-app-title). */
const BUSINESS_APP: AppIdentity = { name: APP_NAME, icon: '/business/icon-192.png', homeScreenName: 'IC Business' };
const ZONE = 'America/Los_Angeles';

function Section({ id, title, lead, children, testId }: { id: string; title: string; lead?: string; children: ReactNode; testId?: string }) {
  return (
    <section className="biz-card biz-settings__section" aria-labelledby={id} data-testid={testId}>
      <h2 id={id} className="biz-card__title">
        {title}
      </h2>
      {lead ? <p className="secondary biz-settings__lead">{lead}</p> : null}
      {children}
    </section>
  );
}

// ---------------------------------------------------------------- Stripe

function StripeSection({ stripe, onChanged }: { stripe: ReturnType<typeof useLoad<StripeConnection>>; onChanged: () => void }) {
  const [params, setParams] = useSearchParams();
  const navigate = useNavigate();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const returned = useRef<string | null>(params.get('stripe'));
  const [result, setResult] = useState<{ text: string; good: boolean } | null>(() => (returned.current ? stripeReturnLine(returned.current) : null));

  // Back from Stripe (/business/settings?stripe=active): the status is checked again, and the address tidied.
  useEffect(() => {
    if (!params.has('stripe')) return;
    const status = params.get('stripe') ?? '';
    setResult(stripeReturnLine(status));
    const next = new URLSearchParams(params);
    next.delete('stripe');
    setParams(next, { replace: true });
    onChanged();
  }, [params, setParams, onChanged]);

  const connect = async () => {
    setBusy(true);
    setError(null);
    setResult(null);
    try {
      const link = await ownerApi.connectStripe();
      // The demo comes straight back to this page; the real thing opens Stripe's page.
      if (link.url.startsWith('/')) {
        navigate(link.url, { replace: true });
        setBusy(false);
      } else {
        leaveTo(link.url);
      }
    } catch (caught) {
      setError(errorMessage(caught));
      setBusy(false);
    }
  };

  const connection = stripe.data;
  const view = connection ? stripeView(connection) : null;
  return (
    <Section id="stripe-title" title="Card payments (Stripe)" testId="stripe-settings">
      <p className="secondary biz-settings__lead">Payments go straight to your own Stripe account. Stripe charges its fees there.</p>
      {result ? (
        result.good ? (
          <SuccessLine testId="stripe-result">
            {result.text}
            {demo() ? ' This is the demo: no real Stripe account was connected.' : ''}
          </SuccessLine>
        ) : (
          <Notice tone="warning" role="status" testId="stripe-result">
            <p>{result.text}</p>
          </Notice>
        )
      ) : null}
      {stripe.status === 'error' && !connection ? <ErrorBanner message={stripe.error} onRetry={stripe.reload} /> : null}
      {connection && view ? (
        <>
          <div className={`biz-status biz-status--${view.tone}`} data-testid="stripe-status">
            <Icon
              name={view.tone === 'good' ? 'check' : view.tone === 'problem' ? 'warning' : view.tone === 'waiting' ? 'clock' : 'info'}
              className="biz-status__icon"
            />
            <div>
              <p className="biz-status__label">
                {view.label}
                {connection.businessName && connection.status !== 'notConnected' ? ` · ${connection.businessName}` : ''}
              </p>
              {/* "Not set up on the server" says it all; the server's "Stripe isn't set up on the server." would say it twice. */}
              {connection.status !== 'off' ? <p className="secondary">{connection.message}</p> : null}
            </div>
          </div>
          <div className="biz-settings__actions">
            {view.action ? (
              <button type="button" className="button button--primary button--large" onClick={() => void connect()} disabled={busy}>
                {busy ? (demo() ? 'Connecting to Stripe (demo)…' : 'Opening Stripe…') : view.action}
              </button>
            ) : null}
            {connection.mode !== 'off' && connection.status !== 'notConnected' && !demo() ? (
              <a className="button button--secondary" href={connection.dashboardUrl} target="_blank" rel="noopener noreferrer">
                Open Stripe Dashboard
                <Icon name="external" className="button__icon" />
              </a>
            ) : null}
          </div>
          {busy && demo() ? <p className="secondary small">Demo: this step stands in for Stripe's own page, where the shop signs in or signs up.</p> : null}
          {error ? (
            <p className="field__error" role="alert">
              <Icon name="error" />
              <span>{error}</span>
            </p>
          ) : null}
          {connection.mode === 'connect' && connection.status !== 'notConnected' ? <p className="secondary small">To disconnect, use the iPhone app.</p> : null}
        </>
      ) : stripe.status !== 'error' ? (
        <SkeletonCard lines={2} label="Loading the Stripe status…" />
      ) : null}
    </Section>
  );
}

// -------------------------------------------------------- No-show protection

function NoShowSection({ stripe }: { stripe: StripeConnection | null }) {
  const catalog = useCatalog();
  const settings = useLoad<NoShowSettings>('no-show-settings', (signal) => ownerApi.noShowSettings(signal));
  const [draft, setDraft] = useState<noShow.NoShowDraft | null>(null);
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const current = settings.data;

  // The form starts from what the server has.
  useEffect(() => {
    if (current && draft === null) setDraft(noShow.draftFrom(current));
  }, [current, draft]);

  if (!current || !draft || !catalog) {
    return (
      <Section id="no-show-title" title="No-show protection" testId="no-show-settings">
        {settings.status === 'error' ? (
          <ErrorBanner title="Couldn't load the settings" message={settings.error} onRetry={settings.reload} />
        ) : (
          <SkeletonCard label="Loading the settings…" />
        )}
      </Section>
    );
  }

  const change = (patch: Partial<noShow.NoShowDraft>) => {
    setDraft({ ...draft, ...patch });
    setSaveError(null);
    setSaved(false);
  };
  const problem = noShow.draftProblem(draft);
  const preview = noShow.draftSettings(draft, current);
  const changed = noShow.hasChanges(draft, current);
  const exampleFee = noShow.exampleFee(preview, catalog);
  const notice = preview && exampleFee !== null ? noShow.clientNotice(exampleFee, exampleFee, preview) : null;
  const policy = preview && exampleFee !== null ? noShow.policyText(exampleFee, exampleFee, preview) : null;
  const stripeLine = noShow.stripeNote(stripe, draft.enabled);

  const save = async () => {
    if (problem) {
      setSaveError(problem);
      return;
    }
    const patch = noShow.draftChanges(draft, current);
    if (Object.keys(patch).length === 0) return;
    setSaving(true);
    setSaveError(null);
    try {
      const result = await ownerApi.updateNoShowSettings(patch);
      settings.replace(result);
      setDraft(noShow.draftFrom(result));
      setSaved(true);
    } catch (caught) {
      setSaveError(errorMessage(caught));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Section
      id="no-show-title"
      title="No-show protection"
      lead="A card on file for online bookings, and the fee for no-shows and late cancellations."
      testId="no-show-settings"
    >
      <label className="biz-switch">
        <input type="checkbox" className="biz-switch__input" checked={draft.enabled} onChange={(e) => change({ enabled: e.target.checked })} />
        <span className="biz-switch__track" aria-hidden="true" />
        <span className="biz-switch__label">No-show protection</span>
      </label>
      <p className="secondary small">{draft.enabled ? noShow.ON_FOOTER : noShow.OFF_FOOTER}</p>
      {stripeLine ? (
        <Notice tone="info" testId="no-show-stripe-note">
          <p>{stripeLine}</p>
        </Notice>
      ) : null}

      <fieldset className="biz-fieldset">
        <legend className="biz-section-title">Fee</legend>
        <div className="segmented">
          <label className="segmented__option">
            <input
              type="radio"
              className="segmented__input"
              name="fee-mode"
              checked={draft.feeMode === 'percent'}
              onChange={() => change({ feeMode: 'percent' })}
            />
            <span className="segmented__label">% of the service</span>
          </label>
          <label className="segmented__option">
            <input type="radio" className="segmented__input" name="fee-mode" checked={draft.feeMode === 'flat'} onChange={() => change({ feeMode: 'flat' })} />
            <span className="segmented__label">Flat amount</span>
          </label>
        </div>
        {draft.feeMode === 'percent' ? (
          <div className="biz-percent">
            <button
              type="button"
              className="biz-stepper__button"
              aria-label="Less"
              disabled={draft.percent <= noShow.STEPPER_MIN}
              onClick={() => change({ percent: noShow.decreasePercent(draft.percent) })}
            >
              −
            </button>
            <span className="biz-percent__value" aria-live="polite" data-testid="no-show-percent">
              {noShow.percentLabel(draft.percent)}
            </span>
            <button
              type="button"
              className="biz-stepper__button"
              aria-label="More"
              disabled={draft.percent >= noShow.PERCENT_MAX}
              onClick={() => change({ percent: noShow.increasePercent(draft.percent) })}
            >
              +
            </button>
          </div>
        ) : (
          <div className="field biz-flat">
            <label className="field__label" htmlFor="flat-fee">
              Flat fee
            </label>
            <div className="biz-money-input">
              <span aria-hidden="true">$</span>
              <input id="flat-fee" className="field__input" inputMode="decimal" value={draft.flatText} onChange={(e) => change({ flatText: e.target.value })} />
            </div>
          </div>
        )}
        <p className="secondary small">{noShow.FEE_FOOTER}</p>
      </fieldset>

      <fieldset className="biz-fieldset">
        <legend className="biz-section-title">Late cancellations</legend>
        <label className="checkbox">
          <input type="checkbox" checked={draft.lateCancelEnabled} onChange={(e) => change({ lateCancelEnabled: e.target.checked })} />
          <span className="checkbox__text">
            <span className="checkbox__label">Charge late cancellations</span>
          </span>
        </label>
        {draft.lateCancelEnabled ? (
          <div className="field biz-window">
            <label className="field__label" htmlFor="late-window">
              Cancelling less than
            </label>
            <select
              id="late-window"
              className="field__input"
              value={draft.lateCancelWindowMinutes}
              onChange={(e) => change({ lateCancelWindowMinutes: Number(e.target.value) })}
            >
              {noShow.windowChoices(draft.lateCancelWindowMinutes).map((minutes) => (
                <option key={minutes} value={minutes}>
                  {windowLabel(minutes)} before
                </option>
              ))}
            </select>
          </div>
        ) : null}
        <p className="secondary small">{noShow.lateCancellationFooter(draft)}</p>
      </fieldset>

      {draft.enabled ? (
        <div className="biz-example">
          <h3 className="biz-section-title">Example</h3>
          {preview ? (
            <ul className="biz-plain-list" role="list">
              {noShow.examples(preview, catalog).map((line) => (
                <li key={line} className="biz-plain-list__row tabular">
                  {line}
                </li>
              ))}
            </ul>
          ) : (
            <p className="secondary">Fix the fee above to see an example.</p>
          )}
          {notice && policy ? (
            <div className="biz-client-view">
              <h3 className="biz-section-title">What clients see</h3>
              <Notice tone="warning" title={notice.title}>
                <p>{notice.message}</p>
              </Notice>
              <p className="secondary small">{policy}</p>
              <p className="secondary small">
                For the example haircut. The notice shows while clients pick a day and time and on Review; they agree to the policy before booking.
              </p>
            </div>
          ) : null}
        </div>
      ) : null}

      {saveError ? (
        <p className="field__error" role="alert" data-testid="no-show-error">
          <Icon name="error" />
          <span>{saveError}</span>
        </p>
      ) : null}
      {saved && !changed ? <SuccessLine testId="no-show-saved">Saved. New bookings use these settings.</SuccessLine> : null}
      <div className="biz-settings__actions">
        <button type="button" className="button button--primary" onClick={() => void save()} disabled={saving || !changed}>
          {saving ? 'Saving…' : 'Save'}
        </button>
        {changed ? (
          <button
            type="button"
            className="button button--secondary"
            onClick={() => {
              setDraft(noShow.draftFrom(current));
              setSaveError(null);
            }}
            disabled={saving}
          >
            Discard changes
          </button>
        ) : null}
      </div>
      <details className="biz-costs">
        <summary>Stripe's costs</summary>
        <p className="secondary small">{noShow.costsText(exampleFee)}</p>
      </details>
    </Section>
  );
}

// ------------------------------------------------------------- Computers

function ComputersSections() {
  const { session: mine } = useSession();
  const computers = useLoad<ComputerSession[]>('computers', (signal) => ownerApi.computerSessions(signal));
  const signOut = useSignOut();
  const [asking, setAsking] = useState<ComputerSession | 'all' | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const list = computers.data;
  const current = list?.find((c) => c.current) ?? null;
  const others = list?.filter((c) => !c.current) ?? [];

  const confirm = async () => {
    if (!asking) return;
    setBusy(true);
    setError(null);
    try {
      if (asking === 'all') {
        await ownerApi.signOutAllComputers();
        session.signOut('Every computer was signed out, this one too. Each needs a new code from the app to sign in again.');
        return;
      }
      await ownerApi.signOutComputer(asking.id);
      setMessage(`Signed out ${asking.name}.`);
      setAsking(null);
      computers.reload();
    } catch (caught) {
      setError(errorMessage(caught));
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      <Section id="this-computer-title" title="This computer" testId="this-computer">
        <dl className="biz-rows">
          <div className="biz-row">
            <dt className="biz-row__label">Name</dt>
            <dd className="biz-row__value">{current?.name ?? mine?.name ?? 'This computer'}</dd>
          </div>
          <div className="biz-row">
            <dt className="biz-row__label">Signed in since</dt>
            <dd className="biz-row__value" data-testid="signed-in-since">
              {dateTimeLabel(new Date(current?.createdAt ?? mine?.createdAt ?? Date.now()), ZONE)}
            </dd>
          </div>
        </dl>
        <p className="secondary small">It stays signed in for 30 days, until you sign out. On a shared computer, sign out when you're done.</p>
        <div className="biz-settings__actions">
          <button type="button" className="button button--secondary" onClick={signOut.ask}>
            Sign out
          </button>
        </div>
      </Section>

      <Section
        id="other-computers-title"
        title="Other computers"
        lead="Computers signed in with a code from the app. Sign out any you don't use."
        testId="other-computers"
      >
        {message ? <SuccessLine>{message}</SuccessLine> : null}
        {computers.status === 'error' ? <ErrorBanner message={computers.error} onRetry={computers.reload} /> : null}
        {list === null ? (
          computers.status !== 'error' ? (
            <SkeletonCard lines={2} label="Loading the computers…" />
          ) : null
        ) : others.length === 0 ? (
          <p className="biz-empty-line">No other computers are signed in.</p>
        ) : (
          <ul className="biz-computers" role="list">
            {others.map((computer) => (
              <li key={computer.id} className="biz-computer" data-testid="computer">
                <div>
                  <p className="biz-computer__name">{computer.name}</p>
                  <p className="secondary small">Last used {dateTimeLabel(new Date(computer.lastUsedAt), ZONE)}</p>
                </div>
                <button type="button" className="button button--secondary" onClick={() => setAsking(computer)} aria-label={`Sign out ${computer.name}`}>
                  Sign out
                </button>
              </li>
            ))}
          </ul>
        )}
        <div className="biz-settings__actions">
          <button type="button" className="text-button text-button--danger" onClick={() => setAsking('all')}>
            Sign out all computers
          </button>
        </div>
      </Section>

      <Dialog
        open={asking !== null}
        title={asking === 'all' ? 'Sign out all computers?' : asking ? `Sign out ${asking.name}?` : ''}
        onClose={() => (busy ? undefined : setAsking(null))}
        testId="confirm-sign-out-computer"
        actions={
          <>
            <button type="button" className="button button--secondary" onClick={() => setAsking(null)} disabled={busy}>
              Keep signed in
            </button>
            <button type="button" className="button button--danger" onClick={() => void confirm()} disabled={busy}>
              {busy ? 'Signing out…' : asking === 'all' ? 'Sign out all' : 'Sign out'}
            </button>
          </>
        }
      >
        <p>
          {asking === 'all'
            ? 'Every computer, this one too, is signed out. Each needs a new code from Izzy Clipz Business on your iPhone to sign in again.'
            : 'It needs a new code from Izzy Clipz Business on your iPhone to sign in again.'}
        </p>
        {error ? (
          <p className="field__error" role="alert">
            <Icon name="error" />
            <span>{error}</span>
          </p>
        ) : null}
      </Dialog>
      {signOut.dialog}
    </>
  );
}

// --------------------------------------------------------- On this device

function InstallSection() {
  const platform = useState(currentPlatform)[0];
  const standalone = useStandalone();
  const [device, setDevice] = useState<Device>(platform.device);
  const install = useInstallPrompt();
  const canInstall = device === platform.device && install.canInstall;
  const url = `${window.location.origin}/business/`;
  return (
    <Section
      id="install-title"
      title={`Put ${APP_NAME} on this phone or computer`}
      lead="It opens in its own window, like an app, with its own icon."
      testId="install-business"
    >
      {standalone ? (
        <SuccessLine>You're using the app.</SuccessLine>
      ) : (
        <div className="biz-install">
          <DevicePicker value={device} onChange={setDevice} name="business-device" />
          {install.installed && device === platform.device ? (
            <Notice tone="success" role="status" title={`${APP_NAME} is installed.`}>
              <p>{device === 'computer' ? "It opens in its own window, and you'll find it with your other apps." : 'Find it on your Home Screen.'}</p>
            </Notice>
          ) : null}
          {canInstall ? <InstallNow app={BUSINESS_APP} onInstall={() => void promptInstall()} /> : null}
          {device === 'iphone' ? (
            <>
              <p className="secondary small" data-testid="iphone-app-note">
                On the iPhone with the Izzy Clipz Business app, use the app: it also takes card payments with Tap to Pay.
              </p>
              <IPhoneSteps browser={platform.device === 'iphone' ? platform.browser : 'safari'} url={url} app={BUSINESS_APP} />
            </>
          ) : null}
          {device === 'android' ? (
            <AndroidSteps orMenu={canInstall} browser={platform.device === 'android' ? platform.browser : 'chrome'} url={url} app={BUSINESS_APP} />
          ) : null}
          {device === 'computer' ? (
            <ComputerSteps
              orAddressBar={canInstall}
              browser={platform.device === 'computer' ? platform.browser : 'chrome'}
              windows={platform.device === 'computer' && platform.windows}
              app={BUSINESS_APP}
            />
          ) : null}
        </div>
      )}
    </Section>
  );
}

// -------------------------------------------------------------------- Demo

function DemoSection({ onReset, done }: { onReset: () => void; done: boolean }) {
  const [asking, setAsking] = useState(false);
  const [busy, setBusy] = useState(false);
  if (!demo()) return null;
  const reset = async () => {
    setBusy(true);
    try {
      await ownerApi.resetDemo();
      onReset();
    } finally {
      setBusy(false);
      setAsking(false);
    }
  };
  return (
    <Section id="demo-title" title="The demo" lead="Everything you change in the demo stays in this browser." testId="demo-settings">
      {done ? <SuccessLine testId="demo-reset">The demo is back as it started: the sample shop, Stripe not connected.</SuccessLine> : null}
      <div className="biz-settings__actions">
        <button type="button" className="button button--secondary" onClick={() => setAsking(true)}>
          Reset the demo
        </button>
      </div>
      <Dialog
        open={asking}
        title="Reset the demo?"
        onClose={() => setAsking(false)}
        testId="confirm-reset-demo"
        actions={
          <>
            <button type="button" className="button button--secondary" onClick={() => setAsking(false)} disabled={busy}>
              Keep my changes
            </button>
            <button type="button" className="button button--primary" onClick={() => void reset()} disabled={busy}>
              {busy ? 'Resetting…' : 'Reset the demo'}
            </button>
          </>
        }
      >
        <p>Checkouts, voids, products and settings you changed go, and the sample shop comes back as it started.</p>
      </Dialog>
    </Section>
  );
}

export function SettingsPage() {
  useBusinessTitle('Settings', 'Card payments with Stripe, no-show protection, and the computers signed in to Izzy Clipz Business.');
  const stripe = useLoad<StripeConnection>('stripe', (signal) => ownerApi.stripe(signal));
  // After "Reset the demo", every section loads again from scratch.
  const [generation, setGeneration] = useState(0);
  return (
    <div className="container biz-page biz-settings" data-testid="settings-page">
      <PageHeader title="Settings" lead="Card payments, no-show protection, and the computers signed in." />
      <div className="biz-settings__sections" key={generation}>
        <StripeSection stripe={stripe} onChanged={stripe.reload} />
        <NoShowSection stripe={stripe.data} />
        <ComputersSections />
        <InstallSection />
      </div>
      <DemoSection
        done={generation > 0}
        onReset={() => {
          setGeneration((n) => n + 1);
          stripe.reload();
        }}
      />
    </div>
  );
}
