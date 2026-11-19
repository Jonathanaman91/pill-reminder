import { ChevronLeft, ChevronRight, X } from 'lucide-react';
import {
  cloneElement, createContext, useCallback, useContext, useEffect, useId, useRef, useState,
} from 'react';
import { formatNumber } from './lib.js';

/** Every icon in the panel uses these, so size and stroke weight never vary. */
export const ICON = { size: 18, strokeWidth: 1.75, 'aria-hidden': true };

// ---------------------------------------------------------------------------
// Buttons
// ---------------------------------------------------------------------------
/** variant: 'primary' (the one accent action on a screen) | 'neutral' | 'quiet' | 'danger' */
export function Button({ variant = 'neutral', busy = false, children, ...props }) {
  return (
    <button
      type="button"
      className={`btn btn-${variant}`}
      aria-busy={busy || undefined}
      {...props}
      disabled={busy || props.disabled}
    >
      {busy && <span className="spinner" aria-hidden="true" />}
      {children}
    </button>
  );
}

/** A row of choices where exactly one is on (All / Active / Suspended). */
export function Segmented({ label, value, onChange, options }) {
  return (
    <div className="segmented" role="group" aria-label={label}>
      {options.map(([key, text]) => (
        <button key={key} type="button" aria-pressed={value === key} onClick={() => onChange(key)}>
          {text}
        </button>
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Form field: label on top, error (or hint) underneath
// ---------------------------------------------------------------------------
export function Field({ label, error, hint, children }) {
  const id = useId();
  const noteId = `${id}-note`;
  return (
    <div className="field">
      <label htmlFor={id}>{label}</label>
      {cloneElement(children, {
        id,
        'aria-invalid': error ? true : undefined,
        'aria-describedby': error || hint ? noteId : undefined,
      })}
      {error
        ? <p id={noteId} className="field-note field-error">{error}</p>
        : hint && <p id={noteId} className="field-note">{hint}</p>}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Dialog — the browser's own <dialog>, which traps focus and handles Esc
// ---------------------------------------------------------------------------
export function Dialog({ title, onClose, children }) {
  const ref = useRef(null);
  const titleId = useId();

  useEffect(() => {
    if (!ref.current.open) ref.current.showModal();
  }, []);

  return (
    <dialog
      ref={ref}
      className="dialog"
      aria-labelledby={titleId}
      onCancel={(e) => { e.preventDefault(); onClose(); }} // Esc
      onMouseDown={(e) => { if (e.target === ref.current) onClose(); }} // click outside
    >
      <div className="dialog-body">
        <header className="dialog-head">
          <h2 id={titleId}>{title}</h2>
          <button type="button" className="icon-btn" aria-label="Close" onClick={onClose}>
            <X {...ICON} />
          </button>
        </header>
        {children}
      </div>
    </dialog>
  );
}

// ---------------------------------------------------------------------------
// Toast — short feedback after every action, like the app's SnackBar
// ---------------------------------------------------------------------------
const ToastContext = createContext(() => {});
export const useToast = () => useContext(ToastContext);

export function ToastProvider({ children }) {
  const [toast, setToast] = useState(null);

  const show = useCallback((message, tone = 'ok') => {
    setToast({ message, tone, key: Date.now() });
  }, []);

  useEffect(() => {
    if (!toast) return undefined;
    const timer = setTimeout(() => setToast(null), toast.tone === 'error' ? 6000 : 4000);
    return () => clearTimeout(timer);
  }, [toast]);

  return (
    <ToastContext.Provider value={show}>
      {children}
      {/* popover="manual" lifts the toast above an open dialog */}
      <ToastView toast={toast} />
    </ToastContext.Provider>
  );
}

function ToastView({ toast }) {
  const ref = useRef(null);
  useEffect(() => {
    const el = ref.current;
    if (!toast || !el?.showPopover) return undefined;
    el.showPopover();
    return () => { if (el.matches(':popover-open')) el.hidePopover(); };
  }, [toast]);

  return (
    <div ref={ref} popover="manual" className="toast" role="status" aria-live="polite" data-tone={toast?.tone}>
      {toast?.message}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Lists: loading rows, empty / error message, page controls
// ---------------------------------------------------------------------------
export function SkeletonRows({ columns, rows = 6 }) {
  return Array.from({ length: rows }, (_, r) => (
    <tr key={r} aria-hidden="true">
      {Array.from({ length: columns }, (_, c) => (
        <td key={c}><span className="bone" style={{ width: c === 0 ? '70%' : '50%' }} /></td>
      ))}
    </tr>
  ));
}

export function Message({ title, children, action }) {
  return (
    <div className="message">
      <p className="message-title">{title}</p>
      {children && <p>{children}</p>}
      {action}
    </div>
  );
}

export function LoadError({ error, onRetry }) {
  return (
    <Message title="Couldn't load this" action={<Button onClick={onRetry}>Try again</Button>}>
      {error.message}
    </Message>
  );
}

export function Pagination({ page, pageSize, total, onPage }) {
  if (total === 0) return null;
  const first = (page - 1) * pageSize + 1;
  const last = Math.min(page * pageSize, total);
  return (
    <nav className="pagination" aria-label="Pages">
      <span>{formatNumber(first)}–{formatNumber(last)} of {formatNumber(total)}</span>
      <button type="button" className="icon-btn" aria-label="Previous page" disabled={page === 1} onClick={() => onPage(page - 1)}>
        <ChevronLeft {...ICON} />
      </button>
      <button type="button" className="icon-btn" aria-label="Next page" disabled={last >= total} onClick={() => onPage(page + 1)}>
        <ChevronRight {...ICON} />
      </button>
    </nav>
  );
}
