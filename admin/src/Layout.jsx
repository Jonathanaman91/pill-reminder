import { ChartColumn, History, LayoutDashboard, LogOut, Pill, Users } from 'lucide-react';
import { useState } from 'react';
import { NavLink, Outlet } from 'react-router-dom';
import { useAuth } from './auth.jsx';
import { ICON } from './ui.jsx';

const LINKS = [
  { to: '/', label: 'Overview', icon: LayoutDashboard, end: true },
  { to: '/analytics', label: 'Analytics', icon: ChartColumn },
  { to: '/users', label: 'Users', icon: Users },
  { to: '/medications', label: 'Medications', icon: Pill },
  { to: '/activity', label: 'Activity', icon: History },
];

export default function Layout() {
  const { user, logout } = useAuth();
  const [leaving, setLeaving] = useState(false);

  return (
    <div className="shell">
      <aside className="sidebar">
        <p className="brand">Pill Reminder</p>
        <nav aria-label="Sections">
          {LINKS.map(({ to, label, icon: Icon, end }) => (
            <NavLink key={to} to={to} end={end} className="nav-link">
              <Icon {...ICON} />
              {label}
            </NavLink>
          ))}
        </nav>
        <div className="account">
          <div className="account-who">
            <p>{user.fullName}</p>
            <p>{user.email}</p>
          </div>
          <button
            type="button"
            className="nav-link"
            disabled={leaving}
            onClick={() => { setLeaving(true); logout(); }}
          >
            <LogOut {...ICON} />
            {leaving ? 'Signing out…' : 'Sign out'}
          </button>
        </div>
      </aside>
      <main className="content">
        <Outlet />
      </main>
    </div>
  );
}
