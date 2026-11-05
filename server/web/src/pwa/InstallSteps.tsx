// How to put an app on the Home Screen (or with a computer's other apps), in a few plain
// steps for each device, with pictures of what to tap: the steps Get the app shows for
// Izzy Clipz, and Izzy Clipz Business's Settings for Business. One Install button does it
// where the browser can (Chrome and Edge).

import { useState, type ReactNode } from 'react';
import { Icon } from '../components/Icon';
import { Notice } from '../components/ui';
import {
  AddButtonDrawing,
  AddressBarInstallDrawing,
  AddToHomeScreenDrawing,
  AndroidMenuDrawing,
  CLIENT_APP,
  InstallAppDrawing,
  InstallDialogDrawing,
  ShareButtonDrawing,
  type AppIdentity,
} from './drawings';
import type { Browser, Device } from './platform';

const DEVICES: { id: Device; label: string }[] = [
  { id: 'iphone', label: 'iPhone' },
  { id: 'android', label: 'Android' },
  { id: 'computer', label: 'Computer' },
];

/** The steps open on the visitor's own device, already picked; the others are one tap away. */
export function DevicePicker({ value, onChange, name = 'device' }: { value: Device; onChange: (device: Device) => void; name?: string }) {
  return (
    <fieldset className="device-picker">
      <legend className="device-picker__legend">Show the steps for</legend>
      <div className="segmented">
        {DEVICES.map((device) => (
          <label key={device.id} className="segmented__option">
            <input type="radio" className="segmented__input" name={name} value={device.id} checked={value === device.id} onChange={() => onChange(device.id)} />
            <span className="segmented__label">{device.label}</span>
          </label>
        ))}
      </div>
    </fieldset>
  );
}

/** Chrome or Edge can install it right now: one button, the browser's own question. */
export function InstallNow({ onInstall, app = CLIENT_APP }: { onInstall: () => void; app?: AppIdentity }) {
  return (
    <div className="install-now card card--gray" data-testid="install-now">
      <p className="install-now__lead">Your browser can add {app.name} for you.</p>
      <button type="button" className="button button--primary button--large" onClick={onInstall}>
        Install {app.name}
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

/** For a link opened inside Instagram or Facebook: copy it, to paste in the phone's own browser. */
export function CopyLink({ url, paste }: { url: string; paste: string }) {
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

export function IPhoneSteps({ browser, url, app = CLIENT_APP }: { browser: Browser; url: string; app?: AppIdentity }) {
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
          In Chrome, Edge or Firefox, tap the Share button next to the address bar, then <strong>Add to Home Screen</strong>. Or follow these steps in
          Safari.
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
        { text: <>Tap <strong>Add</strong>.</>, note: 'If you see Open as Web App, leave it on.', picture: <AddButtonDrawing app={app} /> },
      ]}
      done={`${app.name} is now on your Home Screen. Tap it to open the app.`}
    />
  );
}

export function AndroidSteps({ orMenu, browser, url, app = CLIENT_APP }: { orMenu: boolean; browser: Browser; url: string; app?: AppIdentity }) {
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
        { text: <>Tap <strong>Install</strong>.</>, picture: <InstallDialogDrawing app={app} /> },
      ]}
      done={`${app.name} is now on your Home Screen and with your other apps.`}
      after={<p className="secondary install-steps__more">Using another browser, like Samsung Internet or Firefox? Look for Install or Add to Home screen in its menu.</p>}
    />
  );
}

/** What a computer's own browser can do, when it isn't Chrome or Edge: Safari's Add to Dock, Firefox's taskbar on Windows. */
function otherBrowserNote(browser: Browser, windows: boolean): ReactNode {
  if (browser === 'safari') return 'On a Mac with Safari, choose File, then Add to Dock. Or use Chrome or Edge, like this:';
  if (browser === 'firefox' && windows) {
    return (
      <>
        In Firefox, click <strong>Add tab to taskbar</strong> at the right end of the address bar. Or use Chrome or Edge, like this:
      </>
    );
  }
  return "This browser can't install apps. Use Chrome or Edge, like this:";
}

export function ComputerSteps({ orAddressBar, browser, windows, app = CLIENT_APP }: { orAddressBar: boolean; browser: Browser; windows: boolean; app?: AppIdentity }) {
  return (
    <Steps
      id="computer"
      title={orAddressBar ? 'Or install it from the address bar' : 'On a computer'}
      before={
        browser === 'firefox' || browser === 'safari' || browser === 'other' ? (
          <Notice tone="info" testId="use-chrome-or-edge">
            <p>{otherBrowserNote(browser, windows)}</p>
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
        { text: <>Click <strong>Install</strong>.</>, picture: <InstallDialogDrawing app={app} /> },
      ]}
      done={`${app.name} opens in its own window, and you'll find it with your other apps.`}
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
