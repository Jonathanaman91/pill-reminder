import { useEffect, useState } from 'react';

// Same lists as the backend (src/routes/medications.routes.js) and the app.
export const DOSAGE_FORMS = ['tablet', 'capsule', 'liquid', 'injection', 'inhaler', 'drops', 'cream', 'other'];
export const DOSAGE_UNITS = ['mg', 'mcg', 'g', 'ml', 'IU', 'units', 'puffs', 'drops', '%'];

export const capitalise = (word) => word.charAt(0).toUpperCase() + word.slice(1);

const dateFormat = new Intl.DateTimeFormat('en-MY', { day: 'numeric', month: 'short', year: 'numeric' });
const dateTimeFormat = new Intl.DateTimeFormat('en-MY', {
  day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false,
});
const numberFormat = new Intl.NumberFormat('en-MY');

export const formatDate = (iso) => (iso ? dateFormat.format(new Date(iso)) : 'Never');
export const formatDateTime = (iso) => (iso ? dateTimeFormat.format(new Date(iso)) : 'Never');
export const formatNumber = (n) => numberFormat.format(n);
export const plural = (n, one, many = `${one}s`) => `${formatNumber(n)} ${n === 1 ? one : many}`;

/** One sentence for a row of the audit trail. */
export function describeActivity({ action, label, details }) {
  const name = label ?? 'a deleted item';
  switch (action) {
    case 'user.suspend': return `Suspended ${name}`;
    case 'user.reactivate': return `Reactivated ${name}`;
    case 'user.role':
      return details?.changes?.role?.to === 'admin' ? `Made ${name} an admin` : `Removed admin access from ${name}`;
    case 'user.update': return `Edited ${name}`;
    case 'user.sign_out': return `Signed ${name} out of every device`;
    case 'user.delete': return `Deleted the account ${name}`;
    case 'catalog.create': return `Added ${name} to the medication database`;
    case 'catalog.update': return `Edited ${name} in the medication database`;
    case 'catalog.delete': return `Deleted ${name} from the medication database`;
    default: return `${action} ${name}`;
  }
}

/** Returns `value` only after it has stopped changing for `delay` ms (search boxes). */
export function useDebounced(value, delay = 300) {
  const [settled, setSettled] = useState(value);
  useEffect(() => {
    const timer = setTimeout(() => setSettled(value), delay);
    return () => clearTimeout(timer);
  }, [value, delay]);
  return settled;
}

/**
 * Runs `load()` whenever `deps` change. Keeps the previous data on screen
 * while the next page loads, and ignores answers that arrive out of order.
 */
export function useLoad(load, deps) {
  const [state, setState] = useState({ data: null, error: null, loading: true });
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    let current = true;
    setState((s) => ({ ...s, error: null, loading: true }));
    load().then(
      (data) => current && setState({ data, error: null, loading: false }),
      (error) => current && setState((s) => ({ data: s.data, error, loading: false })),
    );
    return () => { current = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, attempt]);

  return { ...state, reload: () => setAttempt((n) => n + 1) };
}
