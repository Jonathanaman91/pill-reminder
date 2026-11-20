import { Navigate, Route, Routes } from 'react-router-dom';
import { useAuth } from './auth.jsx';
import Layout from './Layout.jsx';
import Activity from './pages/Activity.jsx';
import Analytics from './pages/Analytics.jsx';
import Catalog from './pages/Catalog.jsx';
import Login from './pages/Login.jsx';
import Overview from './pages/Overview.jsx';
import Users from './pages/Users.jsx';
import { Button, Message } from './ui.jsx';

export default function App() {
  const auth = useAuth();

  if (auth.status === 'restoring') {
    return (
      <main className="centered" aria-busy="true">
        <span className="spinner spinner-lg" role="status" aria-label="Signing you in" />
      </main>
    );
  }
  if (auth.status === 'unreachable') {
    return (
      <main className="centered">
        <Message title="Couldn't reach the server" action={<Button onClick={auth.retry}>Try again</Button>}>
          You are still signed in. Check your connection, then try again.
        </Message>
      </main>
    );
  }
  if (auth.status === 'signedOut') return <Login />;

  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<Overview />} />
        <Route path="analytics" element={<Analytics />} />
        <Route path="users" element={<Users />} />
        <Route path="medications" element={<Catalog />} />
        <Route path="activity" element={<Activity />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  );
}
