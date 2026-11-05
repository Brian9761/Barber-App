// Pieces the Business pages share: a page's header, badges, skeletons while loading,
// banners that say what went wrong (with Try again), and the side panel.

import { createContext, Fragment, useEffect, useId, useRef, useState, type ReactNode } from 'react';
import { Icon } from '../../components/Icon';
import type { Badge } from '../lib/fees';

/** A page's title, what it's for in one short line, and its controls on the right. */
export function PageHeader({ title, lead, children, eyebrow }: { title: ReactNode; lead: ReactNode; children?: ReactNode; eyebrow?: ReactNode }) {
  return (
    <header className="biz-header">
      <div className="biz-header__words">
        {eyebrow ? <p className="biz-header__eyebrow">{eyebrow}</p> : null}
        <h1 className="biz-header__title">{title}</h1>
        <p className="biz-header__lead">{lead}</p>
      </div>
      {children ? <div className="biz-header__controls">{children}</div> : null}
    </header>
  );
}

function BadgeText({ text }: { text: string }) {
  return (
    <span>
      {text.split(' · ').map((part, index, parts) => (
        <Fragment key={index}>
          {index > 0 ? ' ' : null}
          <span className="biz-badge__part">{index < parts.length - 1 ? `${part} ·` : part}</span>
        </Fragment>
      ))}
    </span>
  );
}

/**
 * An appointment's badges: its status, what was paid, the card on file or its fee. A list of
 * them, or (`inline`, inside the appointment's button, where a list can't go) plain words.
 */
export function Badges({ badges, testId, inline = false }: { badges: Badge[]; testId?: string; inline?: boolean }) {
  if (inline) {
    return (
      <span className="biz-badges" data-testid={testId}>
        {badges.map((badge, index) => (
          <Fragment key={badge.text}>
            {/* Read as "Booked, Card on file · Visa •••• 4242". */}
            {index > 0 ? <span className="visually-hidden">, </span> : null}
            <span className={`biz-badge biz-badge--${badge.tone}`}>
              <BadgeText text={badge.text} />
            </span>
          </Fragment>
        ))}
      </span>
    );
  }
  return (
    <ul className="biz-badges" aria-label="Status" data-testid={testId}>
      {badges.map((badge) => (
        <li key={badge.text} className={`biz-badge biz-badge--${badge.tone}`}>
          <BadgeText text={badge.text} />
        </li>
      ))}
    </ul>
  );
}

/** A gray block where something is loading. Nothing moves. */
export function Skeleton({ height = 20, width = '100%', className }: { height?: number | string; width?: number | string; className?: string }) {
  return <span className={`biz-skeleton${className ? ` ${className}` : ''}`} style={{ height, width }} aria-hidden="true" />;
}

/** A loading card: a few gray lines, and the words for screen readers. */
export function SkeletonCard({ lines = 3, label = 'Loading…' }: { lines?: number; label?: string }) {
  return (
    <div className="biz-card biz-card--skeleton" role="status">
      <span className="visually-hidden">{label}</span>
      <Skeleton height={22} width="40%" />
      {Array.from({ length: lines }, (_, i) => (
        <Skeleton key={i} height={16} width={`${90 - i * 15}%`} />
      ))}
    </div>
  );
}

/** Something didn't load or didn't work: what happened, and Try again when that can help. */
export function ErrorBanner({ message, onRetry, title }: { message: string; onRetry?: () => void; title?: string }) {
  return (
    <div className="notice notice--error biz-banner" role="alert">
      <Icon name="error" className="notice__icon" />
      <div className="notice__content">
        {title ? <p className="notice__title">{title}</p> : null}
        <p>{message}</p>
        {onRetry ? (
          <div className="notice__actions">
            <button type="button" className="button button--secondary" onClick={onRetry}>
              Try again
            </button>
          </div>
        ) : null}
      </div>
    </div>
  );
}

/** What just happened: "Sold $60 · Cash · Izzy", "Saved." */
export function SuccessLine({ children, testId }: { children: ReactNode; testId?: string }) {
  return (
    <p className="biz-success" role="status" data-testid={testId}>
      <Icon name="check" className="biz-success__icon" />
      <span>{children}</span>
    </p>
  );
}

/**
 * The bottom of the open side panel, below what scrolls: a view puts what must stay in sight
 * there (checkout's total and how they're paying), so what scrolls is never under it.
 */
export const PanelDock = createContext<HTMLElement | null>(null);

/**
 * A panel at the side of the screen (the whole screen on a phone), on the browser's own modal
 * <dialog>: focus stays inside, the page under it can't be reached, Escape and Close close it,
 * and focus goes back where it was. Another view in the open panel (Check out, the receipt)
 * starts at its top, with the focus on its heading, so it's read out and Tab goes on from there.
 */
export function SidePanel({
  open,
  title,
  onClose,
  children,
  footer,
  back,
  testId,
}: {
  open: boolean;
  title: string;
  onClose: () => void;
  children: ReactNode;
  footer?: ReactNode;
  /** "‹ Appointment": a way back inside the panel. */
  back?: { label: string; onBack: () => void };
  testId?: string;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  const titleId = useId();
  const bodyRef = useRef<HTMLDivElement>(null);
  const headingRef = useRef<HTMLHeadingElement>(null);
  const [dock, setDock] = useState<HTMLDivElement | null>(null);
  /** The view shown last while open: null once closed, so opening again starts afresh. */
  const shown = useRef<string | null>(null);

  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    if (open && !dialog.open) {
      if (typeof dialog.showModal === 'function') dialog.showModal();
      else dialog.setAttribute('open', '');
    } else if (!open && dialog.open) {
      if (typeof dialog.close === 'function') dialog.close();
      else dialog.removeAttribute('open');
    }
  }, [open]);

  // A new view in the panel starts at its top, and (when the panel was already open) with the
  // focus on its heading: what was focused (Check out, a picked product) may be gone.
  useEffect(() => {
    if (!open) {
      shown.current = null;
      return;
    }
    bodyRef.current?.scrollTo?.({ top: 0 });
    if (shown.current !== null && shown.current !== title) headingRef.current?.focus({ preventScroll: true });
    shown.current = title;
  }, [open, title]);

  return (
    <dialog
      ref={ref}
      className="biz-panel"
      aria-labelledby={titleId}
      data-testid={testId}
      onCancel={(event) => {
        event.preventDefault();
        onClose();
      }}
    >
      {open ? (
        <PanelDock.Provider value={dock}>
          <div className="biz-panel__frame">
            <div className="biz-panel__top">
              {back ? (
                <button type="button" className="text-button biz-panel__back" onClick={back.onBack}>
                  <Icon name="chevronLeft" />
                  {back.label}
                </button>
              ) : (
                <span />
              )}
              <button type="button" className="biz-panel__close" onClick={onClose}>
                <Icon name="close" />
                <span>Close</span>
              </button>
            </div>
            <div className="biz-panel__body" ref={bodyRef}>
              <h2 id={titleId} className="biz-panel__title" ref={headingRef} tabIndex={-1}>
                {title}
              </h2>
              {children}
            </div>
            <div className="biz-panel__dock" ref={setDock} />
            {footer ? <div className="biz-panel__footer">{footer}</div> : null}
          </div>
        </PanelDock.Provider>
      ) : null}
    </dialog>
  );
}

/** A label and its value, as in the app's details: "Price  $35". */
export function Row({ label, children, testId }: { label: string; children: ReactNode; testId?: string }) {
  return (
    <div className="biz-row" data-testid={testId}>
      <dt className="biz-row__label">{label}</dt>
      <dd className="biz-row__value">{children}</dd>
    </div>
  );
}

/** A jar, drawn, where a product has no photo yet. Decoration. */
export function ProductPlaceholder({ className }: { className: string }) {
  return (
    <span className={className} aria-hidden="true">
      <svg viewBox="0 0 64 64" focusable="false">
        <rect x="20" y="8" width="24" height="10" rx="3" fill="currentColor" />
        <path d="M16 24c0-3.3 2.7-6 6-6h20c3.3 0 6 2.7 6 6v28c0 3.3-2.7 6-6 6H22c-3.3 0-6-2.7-6-6z" fill="currentColor" opacity="0.75" />
        <rect x="22" y="32" width="20" height="12" rx="2" fill="#fff" opacity="0.6" />
      </svg>
    </span>
  );
}
