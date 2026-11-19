import { Search } from 'lucide-react';
import { useState } from 'react';
import { api, qs } from '../api.js';
import { useAuth } from '../auth.jsx';
import { capitalise, formatDate, formatDateTime, formatNumber, plural, useDebounced, useLoad } from '../lib.js';
import {
  Button, Dialog, Field, ICON, LoadError, Message, Pagination, Segmented, SkeletonRows, useToast,
} from '../ui.jsx';

const STATUS_FILTERS = [['', 'All'], ['active', 'Active'], ['suspended', 'Suspended']];

export default function Users() {
  const { user: me } = useAuth();
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState('');
  const [page, setPage] = useState(1);
  const [selected, setSelected] = useState(null);
  const term = useDebounced(search);

  const list = useLoad(
    () => api(`/admin/users${qs({ search: term, status, page })}`),
    [term, status, page],
  );
  const users = list.data?.items;

  return (
    <>
      <header className="page-head">
        <h1>Users</h1>
      </header>

      <div className="toolbar">
        <label className="search">
          <Search {...ICON} />
          <input
            type="search" placeholder="Search by name or email" aria-label="Search users"
            value={search} onChange={(e) => { setSearch(e.target.value); setPage(1); }}
          />
        </label>
        <Segmented
          label="Filter by status" value={status} options={STATUS_FILTERS}
          onChange={(next) => { setStatus(next); setPage(1); }}
        />
      </div>

      <div className="card table-card" aria-busy={list.loading}>
        {list.error && !users ? <LoadError error={list.error} onRetry={list.reload} /> : (
          <div className="table-scroll">
            <table className={list.loading && users ? 'is-stale' : undefined}>
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Role</th>
                  <th>Status</th>
                  <th className="num">Medications</th>
                  <th>Last sign-in</th>
                  <th>Joined</th>
                </tr>
              </thead>
              <tbody>
                {!users && <SkeletonRows columns={6} />}
                {users?.map((u) => (
                  <tr key={u.id}>
                    <td>
                      <button type="button" className="row-link" onClick={() => setSelected(u)}>
                        {u.fullName}{u.id === me.id && ' (you)'}
                      </button>
                      <span className="cell-sub">{u.email}</span>
                    </td>
                    <td>{capitalise(u.role)}</td>
                    <td className={u.status === 'suspended' ? 'is-danger' : undefined}>{capitalise(u.status)}</td>
                    <td className="num">{formatNumber(u.medicationCount)}</td>
                    <td className="nowrap">{formatDateTime(u.lastLoginAt)}</td>
                    <td className="nowrap">{formatDate(u.createdAt)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {users?.length === 0 && (
          <Message title="No users found">
            {term || status ? 'Try a different search or filter.' : 'Accounts appear here once people register in the app.'}
          </Message>
        )}
        {list.data && <Pagination {...list.data} onPage={setPage} />}
      </div>

      {selected && (
        <UserDialog
          user={selected}
          isSelf={selected.id === me.id}
          onClose={() => setSelected(null)}
          onChanged={(updated) => { setSelected(updated); list.reload(); }}
        />
      )}
    </>
  );
}

function UserDialog({ user, isSelf, onClose, onChanged }) {
  const toast = useToast();
  const [fullName, setFullName] = useState(user.fullName);
  const [role, setRole] = useState(user.role);
  const [status, setStatus] = useState(user.status);
  const [fields, setFields] = useState({});
  const [busy, setBusy] = useState(null); // 'save' | 'signOut' | 'delete'
  const [confirmingDelete, setConfirmingDelete] = useState(false);

  /** Runs one action with a loading state, and reports failure in a toast. */
  async function run(name, action) {
    setBusy(name);
    try {
      await action();
    } catch (err) {
      setFields(err.fields ?? {});
      if (Object.keys(err.fields ?? {}).length === 0) toast(err.message, 'error');
    } finally {
      setBusy(null);
    }
  }

  function save(event) {
    event.preventDefault();
    const name = fullName.trim();
    if (name.length < 2) return setFields({ fullName: 'Enter the full name.' });

    const patch = {};
    if (name !== user.fullName) patch.fullName = name;
    if (role !== user.role) patch.role = role;
    if (status !== user.status) patch.status = status;
    if (Object.keys(patch).length === 0) return onClose();

    return run('save', async () => {
      const { user: updated } = await api(`/admin/users/${user.id}`, { method: 'PATCH', body: patch });
      onChanged(updated);
      toast(patch.status === 'suspended' ? `${updated.fullName} is suspended and signed out.` : 'Changes saved.');
      onClose();
    });
  }

  const signOutEverywhere = () => run('signOut', async () => {
    const result = await api(`/admin/users/${user.id}/sign-out`, { method: 'POST' });
    onChanged(result.user);
    toast(`Signed out of ${plural(result.sessionsEnded, 'device')}.`);
  });

  const remove = () => run('delete', async () => {
    await api(`/admin/users/${user.id}`, { method: 'DELETE' });
    onChanged(null);
    toast(`Deleted ${user.email}.`);
    onClose();
  });

  if (confirmingDelete) {
    return (
      <Dialog title="Delete this account?" onClose={onClose}>
        <p className="dialog-text">
          This permanently removes <strong>{user.email}</strong>, with {plural(user.medicationCount, 'medication')} and
          all dose history. It cannot be undone.
        </p>
        <footer className="dialog-actions">
          <Button variant="quiet" onClick={() => setConfirmingDelete(false)} disabled={busy !== null}>Keep account</Button>
          <Button variant="danger" busy={busy === 'delete'} onClick={remove}>Delete account</Button>
        </footer>
      </Dialog>
    );
  }

  return (
    <Dialog title={user.fullName} onClose={onClose}>
      <form onSubmit={save} noValidate>
        <dl className="facts">
          <div><dt>Email</dt><dd>{user.email}</dd></div>
          <div><dt>Joined</dt><dd>{formatDate(user.createdAt)}</dd></div>
          <div><dt>Last sign-in</dt><dd>{formatDateTime(user.lastLoginAt)}</dd></div>
          <div><dt>Medications</dt><dd>{formatNumber(user.medicationCount)}</dd></div>
          <div>
            <dt>Doses taken, last 30 days</dt>
            <dd>{user.doses30d === 0 ? 'No data' : `${formatNumber(user.taken30d)} of ${formatNumber(user.doses30d)}`}</dd>
          </div>
          <div><dt>Signed-in devices</dt><dd>{formatNumber(user.sessionCount)}</dd></div>
        </dl>

        <Field label="Full name" error={fields.fullName}>
          <input value={fullName} maxLength={120} onChange={(e) => setFullName(e.target.value)} />
        </Field>
        <div className="field-row">
          <Field label="Role" hint={isSelf ? 'You cannot change your own role.' : undefined}>
            <select value={role} disabled={isSelf} onChange={(e) => setRole(e.target.value)}>
              <option value="user">User</option>
              <option value="admin">Admin</option>
            </select>
          </Field>
          <Field label="Status" hint={isSelf ? 'You cannot suspend yourself.' : undefined}>
            <select value={status} disabled={isSelf} onChange={(e) => setStatus(e.target.value)}>
              <option value="active">Active</option>
              <option value="suspended">Suspended</option>
            </select>
          </Field>
        </div>

        <footer className="dialog-actions">
          {!isSelf && (
            <Button variant="danger-quiet" onClick={() => setConfirmingDelete(true)} disabled={busy !== null}>
              Delete
            </Button>
          )}
          <Button
            variant="quiet" busy={busy === 'signOut'}
            disabled={busy !== null || user.sessionCount === 0} onClick={signOutEverywhere}
          >
            Sign out everywhere
          </Button>
          <span className="spacer" />
          <Button type="submit" variant="primary" busy={busy === 'save'} disabled={busy !== null}>Save</Button>
        </footer>
      </form>
    </Dialog>
  );
}
