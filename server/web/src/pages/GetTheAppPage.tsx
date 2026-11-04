import { useMemo, useState, type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { Icon } from '../components/Icon';
import { Notice, PreferToCall } from '../components/ui';
import { usePageMeta } from '../components/usePageMeta';
import {
  AddButtonDrawing,
  AddressBarInstallDrawing,
  AddToHomeScreenDrawing,
  AndroidMenuDrawing,
  InstallAppDrawing,
  InstallDialogDrawing,
  ShareButtonDrawing,
} from '../pwa/drawings';
import { promptInstall, useInstallPrompt } from '../pwa/installPrompt';
import { currentPlatform, useStandalone, type Browser, type Device, type Platform } from '../pwa/platform';
import { QrCode } from '../pwa/QrCode';

// "Get the app": how to put Izzy Clipz on the Home Screen, in a few plain steps for the
// visitor's own device (the others one tap away), with pictures of what to tap. Where the
// browser can install it right away (Chrome and Edge), one button does it. On a computer, a
// QR code opens the site on a phone. Opened as the app, it just says so.

const DEVICES: { id: Device; label: string }[] = [
  { id: 'iphone', label: 'iPhone' },
  { id: 'android', label: 'Android' },
  { id: 'computer', label: 'Computer' },
];

export function GetTheAppPage() {
  usePageMeta('Get the app', 'Put Izzy Clipz on your Home Screen: it opens like an app, with no App Store and nothing to pay.');
  const platform = useMemo(currentPlatform, []);
  const standalone = useStandalone();
  return (
    <>
      <header className="page-header container get-app-header">
        <img className="app-icon" src="/icon-192.png" width={96} height={96} alt="" />
        <h1>Get the app.</h1>
        <p className="lead secondary">Put Izzy Clipz on your Home Screen. It opens like an app, with no App Store and nothing to pay.</p>
        <PreferToCall className="page-header__call" />
      </header>
      {standalone ? <UsingTheApp /> : <HowToGetIt platform={platform} />}
    </>
  );
}

function UsingTheApp() {
  return (
    <section className="container container--narrow using-app" aria-labelledby="using-app-title" data-testid="using-the-app">
      <div className="status-message card card--gray">
        <Icon name="check" className="using-app__icon" />
        <h2 id="using-app-title">You're using the app.</h2>
        <p className="lead secondary">Izzy Clipz is on your Home Screen. Open it from there whenever you want to book.</p>
        <Link className="button button--primary button--large" to="/book">
          Book an appointment
        </Link>
      </div>
    </section>
  );
}

function HowToGetIt({ platform }: { platform: Platform }) {
  const [device, setDevice] = useState<Device>(platform.device);
  const [declined, setDeclined] = useState(false);
  const install = useInstallPrompt();
  const url = `${window.location.origin}/app`;
  // The browser's own Install button installs on this device, so it's only offered in this device's steps.
  const canInstall = device === platform.device && install.canInstall;
  const onInstall = async () => {
    const outcome = await promptInstall();
    setDeclined(outcome === 'dismissed');
  };
  return (
    <section className="container get-app" aria-label="How to get the app">
      <DevicePicker value={device} onChange={setDevice} />
      <div className={`get-app__layout${platform.device === 'computer' ? ' get-app__layout--with-code' : ''}`}>
        <div className="get-app__steps">
          {install.installed && device === platform.device ? (
            <Notice tone="success" role="status" title="Izzy Clipz is installed." testId="installed">
              <p>{device === 'computer' ? "It opens in its own window, and you'll find it with your other apps." : 'Find it on your Home Screen.'}</p>
            </Notice>
          ) : null}
          {canInstall ? <InstallNow onInstall={() => void onInstall()} /> : null}
          {declined && !canInstall ? <p className="secondary get-app__declined">No problem. You can install it any time with the steps below.</p> : null}
          {device === 'iphone' ? <IPhoneSteps browser={platform.device === 'iphone' ? platform.browser : 'safari'} url={url} /> : null}
          {device === 'android' ? <AndroidSteps orMenu={canInstall} browser={platform.device === 'android' ? platform.browser : 'chrome'} url={url} /> : null}
          {device === 'computer' ? <ComputerSteps orAddressBar={canInstall} browser={platform.device === 'computer' ? platform.browser : 'chrome'} /> : null}
        </div>
        {platform.device === 'computer' ? <PhoneCode url={url} /> : null}
      </div>
    </section>
  );
}

/** The steps open on the visitor's own device, already picked; the others are one tap away. */
function DevicePicker({ value, onChange }: { value: Device; onChange: (device: Device) => void }) {
  return (
    <fieldset className="device-picker">
      <legend className="device-picker__legend">Show the steps for</legend>
      <div className="segmented">
        {DEVICES.map((device) => (
          <label key={device.id} className="segmented__option">
            <input
              type="radio"
              className="segmented__input"
              name="device"
              value={device.id}
              checked={value === device.id}
              onChange={() => onChange(device.id)}
            />
            <span className="segmented__label">{device.label}</span>
          </label>
        ))}
      </div>
    </fieldset>
  );
}

/** Chrome or Edge can install it right now: one button, the browser's own question. */
function InstallNow({ onInstall }: { onInstall: () => void }) {
  return (
    <div className="install-now card card--gray" data-testid="install-now">
      <p className="install-now__lead">Your browser can add Izzy Clipz for you.</p>
      <button type="button" className="button button--primary button--large" onClick={onInstall}>
        Install Izzy Clipz
      </button>
    </div>
  );
}

interface StepItem {
  text: ReactNode;
  note?: ReactNode;
  picture?: ReactNode;
}

function Steps({ id, title, before, steps, done, after }: { id: string; title: string; before?: ReactNode; steps: StepItem[]; done: string; after?: ReactNode }) {
  return (
    <section className="install-steps" aria-labelledby={`${id}-steps-title`} data-testid={`${id}-steps`}>
      <h2 id={`${id}-steps-title`} className="install-steps__title">
        {title}
      </h2>
      {before}
      {/* role="list": Safari drops a list's meaning when its numbers are drawn by the page. */}
      <ol className="install-steps__list" role="list">
        {steps.map((step, index) => (
          <li key={index} className="install-step">
            <span className="install-step__number" aria-hidden="true">
              {index + 1}
            </span>
            <div className="install-step__words">
              <p className="install-step__text">{step.text}</p>
              {step.note ? <p className="install-step__note">{step.note}</p> : null}
            </div>
            {step.picture ? <div className="install-step__picture">{step.picture}</div> : null}
          </li>
        ))}
      </ol>
      <p className="install-steps__done">
        <Icon name="check" className="install-steps__done-icon" />
        {done}
      </p>
      {after}
    </section>
  );
}

function IPhoneSteps({ browser, url }: { browser: Browser; url: string }) {
  let before: ReactNode = null;
  if (browser === 'inApp') {
    before = (
      <Notice tone="info" title="Open this page in Safari first" testId="open-in-safari">
        <p>You're in another app's browser, which can't add it to your Home Screen. Tap ⋯ or the menu, then Open in browser or Open in Safari.</p>
        <CopyLink url={url} paste="Copied. Open Safari and paste it in the address bar." />
      </Notice>
    );
  } else if (browser === 'chrome' || browser === 'edge' || browser === 'firefox') {
    before = (
      <Notice tone="info" testId="other-iphone-browser">
        <p>
          In Chrome, Edge or Firefox, tap the Share button next to the address bar, then <strong>Add to Home Screen</strong>. Or follow
          these steps in Safari.
        </p>
      </Notice>
    );
  }
  return (
    <Steps
      id="iphone"
      title="On an iPhone or iPad"
      before={before}
      steps={[
        { text: <>Open this page in <strong>Safari</strong>.</> },
        {
          text: <>Tap the <strong>Share</strong> button.</>,
          note: "It's at the bottom of the screen, or at the top on an iPad. Don't see it? Tap ⋯ first, then Share.",
          picture: <ShareButtonDrawing />,
        },
        { text: <>Scroll down and tap <strong>Add to Home Screen</strong>.</>, picture: <AddToHomeScreenDrawing /> },
        { text: <>Tap <strong>Add</strong>.</>, note: 'If you see Open as Web App, leave it on.', picture: <AddButtonDrawing /> },
      ]}
      done="Izzy Clipz is now on your Home Screen. Tap it to open the app."
    />
  );
}

function AndroidSteps({ orMenu, browser, url }: { orMenu: boolean; browser: Browser; url: string }) {
  return (
    <Steps
      id="android"
      title={orMenu ? 'Or use Chrome’s menu' : 'On an Android phone'}
      before={
        browser === 'inApp' ? (
          <Notice tone="info" title="Open this page in Chrome first" testId="open-in-chrome">
            <p>You're in another app's browser, which can't add it to your Home Screen. Tap ⋮ or the menu, then Open in Chrome or Open in browser.</p>
            <CopyLink url={url} paste="Copied. Open Chrome and paste it in the address bar." />
          </Notice>
        ) : null
      }
      steps={[
        { text: <>Open this page in <strong>Chrome</strong>.</> },
        { text: <>Tap the menu <span className="nowrap">⋮</span> at the top right.</>, picture: <AndroidMenuDrawing /> },
        {
          text: <>Tap <strong>Install app</strong>.</>,
          note: 'Some phones say Install and create shortcut, or Add to Home screen.',
          picture: <InstallAppDrawing />,
        },
        { text: <>Tap <strong>Install</strong>.</>, picture: <InstallDialogDrawing /> },
      ]}
      done="Izzy Clipz is now on your Home Screen and with your other apps."
      after={<p className="secondary install-steps__more">Using another browser, like Samsung Internet or Firefox? Look for Install or Add to Home screen in its menu.</p>}
    />
  );
}

function ComputerSteps({ orAddressBar, browser }: { orAddressBar: boolean; browser: Browser }) {
  return (
    <Steps
      id="computer"
      title={orAddressBar ? 'Or install it from the address bar' : 'On a computer'}
      before={
        browser === 'firefox' || browser === 'safari' || browser === 'other' ? (
          <Notice tone="info" testId="use-chrome-or-edge">
            <p>{browser === 'safari' ? 'On a Mac with Safari, choose File, then Add to Dock. Or use Chrome or Edge, like this:' : "This browser can't install apps. Use Chrome or Edge, like this:"}</p>
          </Notice>
        ) : null
      }
      steps={[
        { text: <>Open this page in <strong>Chrome</strong> or <strong>Edge</strong>.</> },
        {
          text: <>Click the <strong>install</strong> button at the right end of the address bar.</>,
          note: "In Edge it says App available. Don't see it? Open the browser's menu and look for Install.",
          picture: <AddressBarInstallDrawing />,
        },
        { text: <>Click <strong>Install</strong>.</>, picture: <InstallDialogDrawing /> },
      ]}
      done="Izzy Clipz opens in its own window, and you'll find it with your other apps."
      after={
        browser === 'safari' ? null : (
          <p className="secondary install-steps__more">
            On a Mac with Safari: choose <strong>File</strong>, then <strong>Add to Dock</strong>.
          </p>
        )
      }
    />
  );
}

/** For a link opened inside Instagram or Facebook: copy it, to paste in the phone's own browser. */
function CopyLink({ url, paste }: { url: string; paste: string }) {
  const [copied, setCopied] = useState<boolean | null>(null);
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
    } catch {
      setCopied(false);
    }
  };
  return (
    <div className="notice__actions">
      <button type="button" className="button button--secondary" onClick={() => void copy()}>
        Copy the link
      </button>
      <p aria-live="polite" className="copy-link__result">
        {copied === true ? paste : copied === false ? `The address is ${url}` : ''}
      </p>
    </div>
  );
}

/** On a computer: a QR code that opens this page on a phone. */
function PhoneCode({ url }: { url: string }) {
  const shown = url.replace(/^https?:\/\//, '');
  return (
    <aside className="phone-code card card--gray" aria-labelledby="phone-code-title" data-testid="phone-code">
      <h2 id="phone-code-title" className="phone-code__title">
        On your phone
      </h2>
      <p>Point your phone's camera at this code to open Izzy Clipz there, then follow the steps for your phone.</p>
      <div className="phone-code__frame">
        <QrCode text={url} label={`QR code that opens ${shown} on your phone`} size={184} />
      </div>
      <p className="phone-code__url" data-testid="phone-code-url">
        {shown}
      </p>
    </aside>
  );
}
