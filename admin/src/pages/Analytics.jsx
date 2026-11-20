import { useState } from 'react';
import { api } from '../api.js';
import { capitalise, formatNumber, plural, useLoad } from '../lib.js';
import { LoadError } from '../ui.jsx';

/**
 * Who uses the app and how well it works, as totals across all users. The
 * server only sends counts per group, so nobody can be picked out here.
 * Every chart is one series in one colour; values are printed on the bars,
 * so no legend is needed and nothing depends on colour alone.
 */
export default function Analytics() {
  const { data, error, reload } = useLoad(() => api('/admin/analytics'), []);

  if (error && !data) return <LoadError error={error} onRetry={reload} />;

  const d = data;
  const logged = d?.adherencePerDay.reduce((s, x) => s + x.logged, 0) ?? 0;
  const taken = d?.adherencePerDay.reduce((s, x) => s + x.taken, 0) ?? 0;

  return (
    <>
      <header className="page-head">
        <div>
          <h1>Analytics</h1>
          <p>Totals across all users. No one can be identified from this page.</p>
        </div>
      </header>

      <dl className="stats" aria-busy={!d}>
        <Stat label="Users" value={d && formatNumber(d.totals.users)} note={d && 'Patient accounts'} />
        <Stat label="Active, last 7 days" value={d && formatNumber(d.totals.active7d)}
          note={d && 'Marked at least one dose'} />
        <Stat label="Health profiles" value={d && formatNumber(d.totals.withProfile)}
          note={d && 'Age or conditions filled in'} />
        <Stat label="Doses taken, 14 days" value={d && (logged ? `${Math.round((taken / logged) * 100)}%` : 'No data')}
          note={d && `${formatNumber(taken)} of ${plural(logged, 'logged dose')}`} />
      </dl>

      <div className="chart-grid">
        <ChartCard title="Doses taken per day" note="Last 14 days, share of logged doses marked taken">
          <Columns
            rows={d?.adherencePerDay}
            value={(r) => r.rate}
            max={100}
            format={(r) => (r.rate === null ? 'No doses' : `${r.rate}%`)}
            tip={(r) => (r.logged ? `${r.label}: ${r.taken} of ${plural(r.logged, 'dose')} taken (${r.rate}%)` : `${r.label}: no doses logged`)}
          />
        </ChartCard>

        <ChartCard title="New accounts per week" note="Last 8 weeks, by week starting">
          <Columns
            rows={d?.signupsPerWeek}
            value={(r) => r.count}
            format={(r) => formatNumber(r.count)}
            tip={(r) => `Week of ${r.label}: ${plural(r.count, 'new account')}`}
          />
        </ChartCard>

        <ChartCard title="Age groups" note="Users per group · doses taken in the last 30 days">
          <Bars
            rows={d?.ageGroups}
            extra={(r) => (r.adherence === null ? '—' : `${r.adherence}% taken`)}
          />
        </ChartCard>

        <ChartCard title="Most common conditions" note="From users' health profiles">
          <Bars rows={d?.conditions} empty="No conditions recorded yet" />
        </ChartCard>

        <ChartCard title="Why doses are skipped" note="Last 30 days">
          <Bars rows={d?.skipReasons} empty="No skipped doses" />
        </ChartCard>

        <ChartCard title="Gender" note="From users' health profiles">
          <Bars rows={d?.genders.map((g) => ({ ...g, label: GENDER[g.label] ?? capitalise(g.label) }))} />
        </ChartCard>

        <ChartCard title="Medication forms" note="Medicines users are tracking">
          <Bars rows={d?.medicationForms.map((f) => ({ ...f, label: capitalise(f.label) }))}
            empty="No medicines yet" />
        </ChartCard>
      </div>
    </>
  );
}

const GENDER = { female: 'Female', male: 'Male', unspecified: 'Prefer not to say', unknown: 'Not given' };

function Stat({ label, value, note }) {
  return (
    <div className="card stat">
      <dt>{label}</dt>
      <dd className="stat-value">{value ?? <span className="bone" style={{ width: 72, height: 32 }} />}</dd>
      <dd className="stat-note">{note ?? <span className="bone" style={{ width: 120 }} />}</dd>
    </div>
  );
}

function ChartCard({ title, note, children }) {
  return (
    <section className="card chart-card">
      <h2>{title}</h2>
      <p className="chart-note">{note}</p>
      {children}
    </section>
  );
}

/** Horizontal bars: label, bar, value. Good for named groups. */
function Bars({ rows, extra, empty = 'No data yet' }) {
  if (!rows) return <div className="bone" style={{ width: '100%', height: 120 }} />;
  const max = Math.max(1, ...rows.map((r) => r.count));
  if (rows.every((r) => r.count === 0)) return <p className="chart-empty">{empty}</p>;
  return (
    <table className="hbars">
      <tbody>
        {rows.map((r) => (
          <tr key={r.label}>
            <th scope="row">{r.label}</th>
            <td className="hbars-track">
              {r.count > 0 && (
                <span className="hbars-bar" style={{ width: `${(r.count / max) * 100}%` }} />
              )}
            </td>
            <td className="num">{formatNumber(r.count)}</td>
            {extra && <td className="num hbars-extra">{extra(r)}</td>}
          </tr>
        ))}
      </tbody>
    </table>
  );
}

/** Vertical columns over time, with a tooltip on hover or focus. */
function Columns({ rows, value, format, tip, max }) {
  const [active, setActive] = useState(null);
  if (!rows) return <div className="bone" style={{ width: '100%', height: 160 }} />;
  const top = max ?? Math.max(1, ...rows.map((r) => value(r) ?? 0));
  const shown = active === null ? null : rows[active];

  return (
    <div className="columns-wrap" onMouseLeave={() => setActive(null)}>
      <p className="columns-tip" aria-live="polite">{shown ? tip(shown) : ' '}</p>
      <div className="columns" role="list">
        {rows.map((r, i) => {
          const v = value(r);
          return (
            <div
              key={r.label}
              role="listitem"
              tabIndex={0}
              aria-label={tip(r)}
              className={`column${active === i ? ' is-active' : ''}`}
              onMouseEnter={() => setActive(i)}
              onFocus={() => setActive(i)}
              onBlur={() => setActive(null)}
            >
              <span className="column-value">{v === null ? '' : format(r)}</span>
              <span className="column-track">
                {v !== null && v > 0 && <span className="column-bar" style={{ height: `${(v / top) * 100}%` }} />}
              </span>
              <span className="column-label">{r.label.split(' ')[0]}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}
