import { Link } from 'react-router-dom';
import { api, qs } from '../api.js';
import { describeActivity, formatDateTime, formatNumber, plural, useLoad } from '../lib.js';
import { LoadError, Message } from '../ui.jsx';

export default function Overview() {
  const stats = useLoad(() => api('/admin/overview'), []);
  const recent = useLoad(() => api(`/admin/activity${qs({ pageSize: 6 })}`), []);

  return (
    <>
      <header className="page-head">
        <h1>Overview</h1>
      </header>

      {stats.error && !stats.data
        ? <LoadError error={stats.error} onRetry={stats.reload} />
        : <StatGrid n={stats.data} />}

      <section className="section">
        <div className="section-head">
          <h2>Recent activity</h2>
          <Link to="/activity" className="text-link">View all</Link>
        </div>
        <div className="card">
          {recent.error && !recent.data && <LoadError error={recent.error} onRetry={recent.reload} />}
          {!recent.data && !recent.error && (
            <ul className="feed" aria-busy="true">
              {[0, 1, 2].map((i) => <li key={i}><span className="bone" style={{ width: '55%' }} /></li>)}
            </ul>
          )}
          {recent.data?.items.length === 0 && (
            <Message title="Nothing yet">Changes made in this panel are recorded here.</Message>
          )}
          {recent.data?.items.length > 0 && (
            <ul className="feed">
              {recent.data.items.map((item) => (
                <li key={item.id}>
                  <span>{describeActivity(item)}</span>
                  <span className="feed-meta">{item.adminName} · {formatDateTime(item.createdAt)}</span>
                </li>
              ))}
            </ul>
          )}
        </div>
      </section>
    </>
  );
}

function StatGrid({ n }) {
  const adherence = n && n.doses7d > 0 ? Math.round((n.taken7d / n.doses7d) * 100) : null;
  const stats = [
    ['Accounts', n && formatNumber(n.accounts), n && `${formatNumber(n.newAccounts7d)} new this week`],
    ['Suspended', n && formatNumber(n.suspended), n && 'Cannot sign in'],
    ['Medications in database', n && formatNumber(n.catalogTotal),
      n && `${formatNumber(n.catalogTotal - n.catalogActive)} hidden from users`],
    ['Doses taken, last 7 days', n && (adherence === null ? 'No data' : `${adherence}%`),
      n && `${formatNumber(n.taken7d)} of ${plural(n.doses7d, 'logged dose')}`],
  ];
  return (
    <dl className="stats" aria-busy={!n}>
      {stats.map(([label, value, note]) => (
        <div key={label} className="card stat">
          <dt>{label}</dt>
          <dd className="stat-value">{value ?? <span className="bone" style={{ width: 72, height: 32 }} />}</dd>
          <dd className="stat-note">{note ?? <span className="bone" style={{ width: 120 }} />}</dd>
        </div>
      ))}
    </dl>
  );
}
