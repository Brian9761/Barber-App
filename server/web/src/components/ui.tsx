import { useId, type CSSProperties, type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { useShopContact } from '../data/catalog';
import { Icon, type IconName } from './Icon';

/** "See services ›": a link that reads as a next step. */
export function MoreLink({ to, href, children, large = false }: { to?: string; href?: string; children: ReactNode; large?: boolean }) {
  const className = `more-link${large ? ' more-link--large' : ''}`;
  const content = (
    <>
      {children}
      <span className="more-link__chevron" aria-hidden="true">
        {' ›'}
      </span>
    </>
  );
  if (href) {
    return (
      <a className={className} href={href}>
        {content}
      </a>
    );
  }
  return (
    <Link className={className} to={to ?? '/'}>
      {content}
    </Link>
  );
}

/**
 * A link that opens in a new tab (one of the shop's policies, from the middle of a booking), so
 * what's on screen stays where it is. Screen readers hear that it opens in a new tab.
 */
export function NewTabLink({ href, className, children, testId }: { href: string; className?: string; children: ReactNode; testId?: string }) {
  return (
    <a className={className} href={href} target="_blank" rel="noopener" data-testid={testId}>
      {children}
      <span className="visually-hidden"> (opens in a new tab)</span>
    </a>
  );
}

/** "(442) 341-3053", tapping calls the shop. */
export function CallLink({ className, children }: { className?: string; children?: ReactNode }) {
  const { phone } = useShopContact();
  return (
    <a className={className} href={`tel:${phone.e164}`}>
      {children ?? phone.display}
    </a>
  );
}

/** "Prefer to call? (442) 341-3053": on every page that books or changes something. */
export function PreferToCall({ className = 'secondary' }: { className?: string }) {
  return (
    <p className={className}>
      Prefer to call? <CallLink className="inline-link nowrap" />
    </p>
  );
}

type NoticeTone = 'info' | 'warning' | 'error' | 'success';

const NOTICE_ICONS: Record<NoticeTone, IconName> = { info: 'info', warning: 'warning', error: 'error', success: 'check' };

/** A boxed message: the fee warning (unmissable), why something didn't work, or good news. */
export function Notice({
  tone,
  title,
  children,
  actions,
  role,
  id,
  testId,
}: {
  tone: NoticeTone;
  title?: ReactNode;
  children?: ReactNode;
  actions?: ReactNode;
  role?: 'alert' | 'status';
  id?: string;
  testId?: string;
}) {
  return (
    <div className={`notice notice--${tone}`} role={role} id={id} data-testid={testId}>
      <Icon name={NOTICE_ICONS[tone]} className="notice__icon" />
      <div className="notice__content">
        {title ? <p className="notice__title">{title}</p> : null}
        {children}
        {actions ? <div className="notice__actions">{actions}</div> : null}
      </div>
    </div>
  );
}

/** A barber's tile: two letters on the apps' colors. Decorative: the name is always next to it. */
export function Monogram({ letters, tone, size }: { letters: string; tone: 'bone' | 'blue' | 'ink'; size?: 'small' | 'medium' | 'large' }) {
  return (
    <span className={`monogram monogram--${tone}${size ? ` monogram--${size}` : ''}`} aria-hidden="true">
      {letters}
    </span>
  );
}

const STAR = 'M12 2.6l2.9 6 6.5.8-4.8 4.5 1.2 6.5L12 17.2l-5.8 3.2 1.2-6.5L2.6 9.4l6.5-.8z';

/** Five stars, filled to `rating` (halves round to the nearest half). Labeled for screen readers. */
export function Stars({ rating, size = 18 }: { rating: number; size?: number }) {
  const id = useId();
  const halves = Math.round(rating * 2);
  return (
    <span className="stars" role="img" aria-label={`${rating} out of 5 stars`} style={{ fontSize: size }}>
      {[0, 1, 2, 3, 4].map((i) => {
        const fill = halves >= (i + 1) * 2 ? 'full' : halves === i * 2 + 1 ? 'half' : 'empty';
        return (
          <svg key={i} viewBox="0 0 24 24" aria-hidden="true" focusable="false">
            {fill === 'half' ? (
              <defs>
                <clipPath id={`${id}-half`}>
                  <rect x="0" y="0" width="12" height="24" />
                </clipPath>
              </defs>
            ) : null}
            <path d={STAR} fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" />
            {fill === 'full' ? <path d={STAR} fill="currentColor" /> : null}
            {fill === 'half' ? <path d={STAR} fill="currentColor" clipPath={`url(#${id}-half)`} /> : null}
          </svg>
        );
      })}
    </span>
  );
}

export function Loading({ text }: { text: string }) {
  return (
    <div className="loading" role="status">
      <span className="spinner" aria-hidden="true" />
      <span>{text}</span>
    </div>
  );
}

/** Something couldn't load: what happened, Try again, and the phone number. */
export function ErrorState({ title, message, onRetry }: { title: string; message: string; onRetry?: () => void }) {
  return (
    <div className="status-message" role="alert">
      <h2>{title}</h2>
      <p className="lead secondary">{message}</p>
      <div className="actions actions--center">
        {onRetry ? (
          <button type="button" className="button button--primary" onClick={onRetry}>
            Try again
          </button>
        ) : null}
        <CallLink className="button button--secondary">
          <Icon name="phone" className="button__icon" /> Call the shop
        </CallLink>
      </div>
    </div>
  );
}

export interface PhotoSource {
  src: string;
  width: number;
}

/** A photo with its sizes, so the browser picks the right one; lazy unless it's at the top of the page. */
export function Photo({
  sources,
  alt,
  width,
  height,
  sizes,
  eager = false,
  className,
  style,
}: {
  sources: PhotoSource[];
  alt: string;
  width: number;
  height: number;
  sizes: string;
  eager?: boolean;
  className?: string;
  style?: CSSProperties;
}) {
  const largest = sources[sources.length - 1]!;
  return (
    <img
      className={className}
      src={largest.src}
      srcSet={sources.map((s) => `${s.src} ${s.width}w`).join(', ')}
      sizes={sizes}
      width={width}
      height={height}
      alt={alt}
      loading={eager ? 'eager' : 'lazy'}
      decoding="async"
      style={style}
    />
  );
}
