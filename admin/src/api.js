// Talks to the backend. Handles the two tokens so pages never have to:
//   access token  — 15 minutes, kept only in memory (gone when the tab closes)
//   refresh token — kept in sessionStorage, so a page reload stays signed in
//                   but closing the tab signs out, and two tabs never share
//                   (and fight over) one token.
const BASE = (import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000/api/v1').replace(/\/$/, '');
const REFRESH_KEY = 'pill-admin.refresh';

let accessToken = null;
let refreshing = null; // the one refresh call in flight, shared by everyone waiting
let onSignedOut = () => {};

export class ApiError extends Error {
  constructor(status, message, fields) {
    super(message);
    this.status = status; // 0 = the server could not be reached
    this.fields = fields ?? {};
  }
}

export const hasSavedSession = () => sessionStorage.getItem(REFRESH_KEY) !== null;
export const setOnSignedOut = (fn) => { onSignedOut = fn; };

function setSession({ accessToken: access, refreshToken }) {
  accessToken = access;
  sessionStorage.setItem(REFRESH_KEY, refreshToken);
}

function clearSession() {
  accessToken = null;
  sessionStorage.removeItem(REFRESH_KEY);
}

async function send(path, { method = 'GET', body, auth = true } = {}) {
  let res;
  try {
    res = await fetch(BASE + path, {
      method,
      headers: {
        ...(body !== undefined && { 'Content-Type': 'application/json' }),
        ...(auth && accessToken && { Authorization: `Bearer ${accessToken}` }),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch {
    throw new ApiError(0, "Couldn't reach the server. Check your connection and try again.");
  }
  if (res.status === 204) return null;
  const data = await res.json().catch(() => null);
  if (!res.ok) throw new ApiError(res.status, data?.error ?? `Request failed (${res.status}).`, data?.fields);
  return data;
}

/**
 * Swaps the refresh token for a new pair. The server treats a refresh token
 * used twice as stolen and ends every session, so all callers share one call.
 */
function refresh() {
  refreshing ??= (async () => {
    const refreshToken = sessionStorage.getItem(REFRESH_KEY);
    if (!refreshToken) throw new ApiError(401, 'Not signed in.');
    try {
      const data = await send('/auth/refresh', {
        method: 'POST',
        body: { refreshToken, deviceName: 'Admin panel' },
        auth: false,
      });
      setSession(data);
      return data.user;
    } catch (err) {
      if (err.status !== 0) clearSession(); // rejected, not merely offline
      throw err;
    }
  })().finally(() => { refreshing = null; });
  return refreshing;
}

/** Call any endpoint that needs a signed-in admin. */
export async function api(path, options) {
  try {
    if (!accessToken) await refresh();
    try {
      return await send(path, options);
    } catch (err) {
      if (err.status !== 401) throw err;
      await refresh(); // access token ran out: get a new one and try once more
      return await send(path, options);
    }
  } catch (err) {
    // 401 = session over. 403 = no longer an admin (demoted or suspended).
    if (err.status === 401 || err.status === 403) {
      clearSession();
      onSignedOut();
    }
    throw err;
  }
}

/** Builds "?search=abc&page=2", leaving out empty values. */
export function qs(params) {
  const filled = Object.entries(params).filter(([, v]) => v !== '' && v !== null && v !== undefined);
  return filled.length ? `?${new URLSearchParams(filled)}` : '';
}

export async function signIn(email, password) {
  const data = await send('/auth/login', { method: 'POST', body: { email, password }, auth: false });
  if (data.user.role !== 'admin') {
    // A normal user's password is correct, but this panel is not for them:
    // end the session that login just created and say why.
    await send('/auth/logout', { method: 'POST', body: { refreshToken: data.refreshToken }, auth: false })
      .catch(() => {});
    throw new ApiError(403, 'This account is not an admin.');
  }
  setSession(data);
  return data.user;
}

/** After a page reload: use the saved refresh token to get back in. */
export async function restoreSession() {
  const user = await refresh();
  if (user.role !== 'admin') {
    await signOut();
    throw new ApiError(403, 'This account is not an admin.');
  }
  return user;
}

export async function signOut() {
  const refreshToken = sessionStorage.getItem(REFRESH_KEY);
  clearSession();
  if (refreshToken) {
    await send('/auth/logout', { method: 'POST', body: { refreshToken }, auth: false }).catch(() => {});
  }
}
