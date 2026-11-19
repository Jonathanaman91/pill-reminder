import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import { hasSavedSession, restoreSession, setOnSignedOut, signIn, signOut } from './api.js';

const AuthContext = createContext(null);
export const useAuth = () => useContext(AuthContext);

/**
 * status: 'restoring'   — page just loaded, checking the saved session
 *         'unreachable' — saved session exists but the server did not answer
 *         'signedOut' | 'signedIn'
 */
export function AuthProvider({ children }) {
  const [state, setState] = useState(() => ({ status: hasSavedSession() ? 'restoring' : 'signedOut' }));

  const restore = useCallback(async () => {
    setState({ status: 'restoring' });
    try {
      setState({ status: 'signedIn', user: await restoreSession() });
    } catch (err) {
      setState({ status: err.status === 0 ? 'unreachable' : 'signedOut' });
    }
  }, []);

  useEffect(() => {
    setOnSignedOut(() => setState({ status: 'signedOut' }));
    if (hasSavedSession()) restore();
  }, [restore]);

  const value = useMemo(() => ({
    ...state,
    retry: restore,
    async login(email, password) {
      setState({ status: 'signedIn', user: await signIn(email, password) });
    },
    async logout() {
      await signOut();
      setState({ status: 'signedOut' });
    },
  }), [state, restore]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}
