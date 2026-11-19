import { Plus, Search } from 'lucide-react';
import { useState } from 'react';
import { api, qs } from '../api.js';
import { capitalise, DOSAGE_FORMS, DOSAGE_UNITS, formatDate, useDebounced, useLoad } from '../lib.js';
import {
  Button, Dialog, Field, ICON, LoadError, Message, Pagination, Segmented, SkeletonRows, useToast,
} from '../ui.jsx';

const STATUS_FILTERS = [['', 'All'], ['active', 'Shown'], ['hidden', 'Hidden']];
const BLANK = {
  genericName: '', brandName: '', form: 'tablet', strength: null, strengthUnit: 'mg',
  description: '', warnings: '', isActive: true,
};

const strengthText = (m) => (m.strength === null ? 'Not set' : `${m.strength} ${m.strengthUnit}`);

export default function Catalog() {
  const [search, setSearch] = useState('');
  const [form, setForm] = useState('');
  const [status, setStatus] = useState('');
  const [page, setPage] = useState(1);
  const [editing, setEditing] = useState(null); // a catalog item, or BLANK for a new one
  const term = useDebounced(search);

  const list = useLoad(
    () => api(`/admin/catalog${qs({ search: term, form, status, page })}`),
    [term, form, status, page],
  );
  const items = list.data?.items;
  const filtered = Boolean(term || form || status);

  return (
    <>
      <header className="page-head">
        <div>
          <h1>Medications</h1>
          <p>The shared medication database for every app user.</p>
        </div>
        <Button variant="primary" onClick={() => setEditing(BLANK)}>
          <Plus {...ICON} />
          Add medication
        </Button>
      </header>

      <div className="toolbar">
        <label className="search">
          <Search {...ICON} />
          <input
            type="search" placeholder="Search by generic or brand name" aria-label="Search medications"
            value={search} onChange={(e) => { setSearch(e.target.value); setPage(1); }}
          />
        </label>
        <select aria-label="Filter by form" value={form} onChange={(e) => { setForm(e.target.value); setPage(1); }}>
          <option value="">All forms</option>
          {DOSAGE_FORMS.map((f) => <option key={f} value={f}>{capitalise(f)}</option>)}
        </select>
        <Segmented
          label="Filter by visibility" value={status} options={STATUS_FILTERS}
          onChange={(next) => { setStatus(next); setPage(1); }}
        />
      </div>

      <div className="card table-card" aria-busy={list.loading}>
        {list.error && !items ? <LoadError error={list.error} onRetry={list.reload} /> : (
          <div className="table-scroll">
            <table className={list.loading && items ? 'is-stale' : undefined}>
              <thead>
                <tr>
                  <th>Medication</th>
                  <th>Form</th>
                  <th className="num">Strength</th>
                  <th>Visibility</th>
                  <th>Updated</th>
                </tr>
              </thead>
              <tbody>
                {!items && <SkeletonRows columns={5} />}
                {items?.map((m) => (
                  <tr key={m.id}>
                    <td>
                      <button type="button" className="row-link" onClick={() => setEditing(m)}>{m.genericName}</button>
                      {m.brandName && <span className="cell-sub">{m.brandName}</span>}
                    </td>
                    <td>{capitalise(m.form)}</td>
                    <td className="num">{strengthText(m)}</td>
                    <td className={m.isActive ? undefined : 'is-muted'}>{m.isActive ? 'Shown' : 'Hidden'}</td>
                    <td className="nowrap">{formatDate(m.updatedAt)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {items?.length === 0 && (
          <Message title={filtered ? 'No medications found' : 'The database is empty'}>
            {filtered ? 'Try a different search or filter.' : 'Add the first medication to get started.'}
          </Message>
        )}
        {list.data && <Pagination {...list.data} onPage={setPage} />}
      </div>

      {editing && (
        <CatalogDialog item={editing} onClose={() => setEditing(null)} onSaved={list.reload} />
      )}
    </>
  );
}

function CatalogDialog({ item, onClose, onSaved }) {
  const toast = useToast();
  const isNew = !item.id;
  const [values, setValues] = useState({
    ...item,
    brandName: item.brandName ?? '',
    strength: item.strength === null ? '' : String(item.strength),
    strengthUnit: item.strengthUnit ?? 'mg',
    description: item.description ?? '',
    warnings: item.warnings ?? '',
  });
  const [fields, setFields] = useState({});
  const [busy, setBusy] = useState(null); // 'save' | 'delete'
  const [confirmingDelete, setConfirmingDelete] = useState(false);

  const set = (key) => (e) => setValues((v) => ({
    ...v, [key]: e.target.type === 'checkbox' ? e.target.checked : e.target.value,
  }));

  /** The same rules as the server, checked first so mistakes show instantly. */
  function validate() {
    const errors = {};
    if (values.genericName.trim().length < 2) errors.genericName = 'Enter the generic name.';
    const strength = values.strength.trim();
    if (strength !== '') {
      const n = Number(strength);
      if (!Number.isFinite(n) || n <= 0) errors.strength = 'Enter a number more than 0.';
      else if (n > 100000) errors.strength = 'That strength is too large.';
    }
    return errors;
  }

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
    const errors = validate();
    setFields(errors);
    if (Object.keys(errors).length > 0) return undefined;

    const strength = values.strength.trim();
    const body = {
      genericName: values.genericName.trim(),
      brandName: values.brandName.trim() || null,
      form: values.form,
      strength: strength === '' ? null : Number(strength),
      strengthUnit: strength === '' ? null : values.strengthUnit,
      description: values.description.trim() || null,
      warnings: values.warnings.trim() || null,
      isActive: values.isActive,
    };
    return run('save', async () => {
      await api(isNew ? '/admin/catalog' : `/admin/catalog/${item.id}`, { method: isNew ? 'POST' : 'PUT', body });
      onSaved();
      toast(isNew ? `Added ${body.genericName}.` : 'Changes saved.');
      onClose();
    });
  }

  const remove = () => run('delete', async () => {
    await api(`/admin/catalog/${item.id}`, { method: 'DELETE' });
    onSaved();
    toast(`Deleted ${item.genericName}.`);
    onClose();
  });

  if (confirmingDelete) {
    return (
      <Dialog title="Delete this medication?" onClose={onClose}>
        <p className="dialog-text">
          <strong>{item.genericName}</strong> will be removed from the database. People who already track it
          keep their own copy. To take it out of the app without deleting it, hide it instead.
        </p>
        <footer className="dialog-actions">
          <Button variant="quiet" onClick={() => setConfirmingDelete(false)} disabled={busy !== null}>Keep it</Button>
          <Button variant="danger" busy={busy === 'delete'} onClick={remove}>Delete medication</Button>
        </footer>
      </Dialog>
    );
  }

  return (
    <Dialog title={isNew ? 'Add medication' : 'Edit medication'} onClose={onClose}>
      <form onSubmit={save} noValidate>
        <Field label="Generic name" error={fields.genericName} hint="For example, Metformin">
          <input value={values.genericName} maxLength={150} autoFocus={isNew} onChange={set('genericName')} />
        </Field>
        <Field label="Brand name (optional)" error={fields.brandName} hint="For example, Glucophage">
          <input value={values.brandName} maxLength={150} onChange={set('brandName')} />
        </Field>
        <div className="field-row field-row-3">
          <Field label="Form" error={fields.form}>
            <select value={values.form} onChange={set('form')}>
              {DOSAGE_FORMS.map((f) => <option key={f} value={f}>{capitalise(f)}</option>)}
            </select>
          </Field>
          <Field label="Strength (optional)" error={fields.strength}>
            <input value={values.strength} inputMode="decimal" placeholder="500" onChange={set('strength')} />
          </Field>
          <Field label="Unit" error={fields.strengthUnit}>
            <select value={values.strengthUnit} onChange={set('strengthUnit')}>
              {DOSAGE_UNITS.map((u) => <option key={u} value={u}>{u}</option>)}
            </select>
          </Field>
        </div>
        <Field label="What it is for (optional)" error={fields.description}>
          <textarea rows={2} maxLength={2000} value={values.description} onChange={set('description')} />
        </Field>
        <Field label="Warnings (optional)" error={fields.warnings}>
          <textarea rows={2} maxLength={2000} value={values.warnings} onChange={set('warnings')} />
        </Field>
        <label className="check">
          <input type="checkbox" checked={values.isActive} onChange={set('isActive')} />
          Show to app users
        </label>

        <footer className="dialog-actions">
          {!isNew && (
            <Button variant="danger-quiet" onClick={() => setConfirmingDelete(true)} disabled={busy !== null}>
              Delete
            </Button>
          )}
          <span className="spacer" />
          <Button variant="quiet" onClick={onClose} disabled={busy !== null}>Cancel</Button>
          <Button type="submit" variant="primary" busy={busy === 'save'} disabled={busy !== null}>
            {isNew ? 'Add medication' : 'Save'}
          </Button>
        </footer>
      </form>
    </Dialog>
  );
}
