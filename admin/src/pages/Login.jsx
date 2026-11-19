import { useEffect, useState } from 'react';
import { useAuth } from '../auth.jsx';
import { Button, Field } from '../ui.jsx';

export default function Login() {
  const { login } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [slow, setSlow] = useState(false);
  const [error, setError] = useState(null);
  const [fields, setFields] = useState({});

  // The free server sleeps when idle and takes up to a minute to wake.
  // Say so after 5 seconds, so a long wait does not look like a broken page.
  useEffect(() => {
    if (!busy) return undefined;
    const timer = setTimeout(() => setSlow(true), 5000);
    return () => { clearTimeout(timer); setSlow(false); };
  }, [busy]);

  async function submit(event) {
    event.preventDefault();
    const missing = {};
    if (!email.trim()) missing.email = 'Enter your email.';
    if (!password) missing.password = 'Enter your password.';
    setFields(missing);
    setError(null);
    if (Object.keys(missing).length > 0) return;

    setBusy(true);
    try {
      await login(email.trim(), password); // success swaps this screen for the panel
    } catch (err) {
      setFields(err.fields ?? {});
      setError(Object.keys(err.fields ?? {}).length > 0 ? null : err.message);
      setBusy(false);
    }
  }

  return (
    <main className="centered">
      <form className="login" onSubmit={submit} noValidate>
        <div>
          <p className="brand">Pill Reminder</p>
          <h1>Admin sign in</h1>
        </div>
        <Field label="Email" error={fields.email}>
          <input
            type="email" autoComplete="username" autoFocus
            value={email} onChange={(e) => setEmail(e.target.value)}
          />
        </Field>
        <Field label="Password" error={fields.password}>
          <input
            type="password" autoComplete="current-password"
            value={password} onChange={(e) => setPassword(e.target.value)}
          />
        </Field>
        {error && <p className="form-error" role="alert">{error}</p>}
        <Button type="submit" variant="primary" busy={busy}>Sign in</Button>
        <p className="field-note" role="status">
          {slow ? 'Waking up the server. This can take up to a minute.' : ''}
        </p>
      </form>
    </main>
  );
}
