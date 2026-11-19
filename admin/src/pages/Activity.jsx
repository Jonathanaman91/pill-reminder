import { useState } from 'react';
import { api, qs } from '../api.js';
import { describeActivity, formatDateTime, useLoad } from '../lib.js';
import { LoadError, Message, Pagination, SkeletonRows } from '../ui.jsx';

export default function Activity() {
  const [page, setPage] = useState(1);
  const list = useLoad(() => api(`/admin/activity${qs({ page })}`), [page]);
  const items = list.data?.items;

  return (
    <>
      <header className="page-head">
        <div>
          <h1>Activity</h1>
          <p>Every change made in this panel, newest first.</p>
        </div>
      </header>

      <div className="card table-card" aria-busy={list.loading}>
        {list.error && !items ? <LoadError error={list.error} onRetry={list.reload} /> : (
          <div className="table-scroll">
            <table className={list.loading && items ? 'is-stale' : undefined}>
              <thead>
                <tr>
                  <th>When</th>
                  <th>Admin</th>
                  <th>Change</th>
                </tr>
              </thead>
              <tbody>
                {!items && <SkeletonRows columns={3} />}
                {items?.map((item) => (
                  <tr key={item.id}>
                    <td className="nowrap">{formatDateTime(item.createdAt)}</td>
                    <td className="nowrap">{item.adminName}</td>
                    <td className="wide">{describeActivity(item)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {items?.length === 0 && (
          <Message title="Nothing yet">Changes to users and medications are recorded here.</Message>
        )}
        {list.data && <Pagination {...list.data} onPage={setPage} />}
      </div>
    </>
  );
}
