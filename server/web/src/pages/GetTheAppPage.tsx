import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { Icon } from '../components/Icon';
import { Notice, PreferToCall } from '../components/ui';
import { usePageMeta } from '../components/usePageMeta';
import { DemoNotice } from '../demo/DemoNotice';
import { isDemo } from '../demo/mode';
import { promptInstall, useInstallPrompt } from '../pwa/installPrompt';
import { AndroidSteps, ComputerSteps, DevicePicker, InstallNow, IPhoneSteps } from '../pwa/InstallSteps';
import { currentPlatform, thisDevice, useStandalone, type Device, type Platform } from '../pwa/platform';
import { QrCode } from '../pwa/QrCode';

// "Get the app": how to put Izzy Clipz on the Home Screen, in a few plain steps for the
// visitor's own device (the others one tap away), with pictures of what to tap. Where the
// browser can install it right away (Chrome and Edge), one button does it. On a computer, a
// QR code opens the site on a phone. Opened as the app, it just says so.

export function GetTheAppPage() {
  usePageMeta('Get the app', 'Put Izzy Clipz on your phone or computer: it opens like an app, with no App Store and nothing to pay.');
  const platform = useMemo(currentPlatform, []);
  const standalone = useStandalone();
  const computer = platform.device === 'computer';
  return (
    <>
      <header className="page-header container get-app-header">
        <img className="app-icon" src="/icon-192.png" width={96} height={96} alt="" />
        <h1>Get the app.</h1>
        <p className="lead secondary" data-testid="get-app-lead">
          {computer
            ? 'Put Izzy Clipz with your other apps. It opens in its own window, with no App Store and nothing to pay.'
            : 'Put Izzy Clipz on your Home Screen. It opens like an app, with no App Store and nothing to pay.'}
        </p>
        <PreferToCall className="page-header__call" />
      </header>
      {/* The demo says what it is here too, before anyone adds it: its bookings never reach the shop. */}
      {isDemo() ? (
        <div className="container container--narrow get-app-demo">
          <DemoNotice />
        </div>
      ) : null}
      {standalone ? <UsingTheApp computer={computer} /> : <HowToGetIt platform={platform} />}
      <div className="container get-app-privacy">
        <p className="secondary" data-testid="get-app-privacy">
          It's this website, installed: our <Link to="/privacy">Privacy Policy</Link> explains what it keeps on your {thisDevice()}.
        </p>
      </div>
    </>
  );
}

function UsingTheApp({ computer }: { computer: boolean }) {
  return (
    <section className="container container--narrow using-app" aria-labelledby="using-app-title" data-testid="using-the-app">
      <div className="status-message card card--gray">
        <Icon name="check" className="using-app__icon" />
        <h2 id="using-app-title">You're using the app.</h2>
        <p className="lead secondary">
          {computer
            ? 'Izzy Clipz is with your other apps. Open it from there whenever you want to book.'
            : 'Izzy Clipz is on your Home Screen. Open it from there whenever you want to book.'}
        </p>
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
          {device === 'computer' ? (
            <ComputerSteps
              orAddressBar={canInstall}
              browser={platform.device === 'computer' ? platform.browser : 'chrome'}
              windows={platform.device === 'computer' && platform.windows}
            />
          ) : null}
        </div>
        {platform.device === 'computer' ? <PhoneCode url={url} /> : null}
      </div>
    </section>
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
