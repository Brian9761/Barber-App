import { useEffect, useId, useRef, type ReactNode } from 'react';

/**
 * A modal question, on the browser's own <dialog>: it keeps focus inside, the rest
 * of the page can't be reached, Escape closes it, and focus goes back where it was.
 * The first button gets focus, so put the safe answer first ("Keep appointment").
 */
export function Dialog({
  open,
  title,
  children,
  actions,
  onClose,
  testId,
}: {
  open: boolean;
  title: string;
  children: ReactNode;
  actions: ReactNode;
  onClose: () => void;
  testId?: string;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  const titleId = useId();
  const bodyId = useId();

  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    if (open && !dialog.open) {
      // Test DOMs (jsdom) don't have showModal.
      if (typeof dialog.showModal === 'function') dialog.showModal();
      else dialog.setAttribute('open', '');
    } else if (!open && dialog.open) {
      if (typeof dialog.close === 'function') dialog.close();
      else dialog.removeAttribute('open');
    }
  }, [open]);

  return (
    <dialog
      ref={ref}
      className="dialog"
      aria-labelledby={titleId}
      aria-describedby={bodyId}
      data-testid={testId}
      onCancel={(event) => {
        event.preventDefault();
        onClose();
      }}
    >
      {open ? (
        <div className="dialog__body">
          <h2 id={titleId} className="dialog__title">
            {title}
          </h2>
          <div id={bodyId} className="dialog__message">
            {children}
          </div>
          <div className="dialog__actions">{actions}</div>
        </div>
      ) : null}
    </dialog>
  );
}
