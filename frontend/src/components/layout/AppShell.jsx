import { NavLink, Outlet } from 'react-router-dom';
import { useQuery } from 'react-query';
import { useAuth } from '../../hooks/useAuth';
import { fetchWallet } from '../../features/portfolio/portfolioService';

export default function AppShell() {
  const { user, logout } = useAuth();
  const walletQuery = useQuery({
    queryKey: ['topbar-wallet'],
    queryFn: fetchWallet
  });

  const navItems = [
    { to: '/markets', label: 'Markets' },
    { to: '/trade', label: 'Trade' },
    { to: '/orders', label: 'Orders' },
    { to: '/portfolio', label: 'Portfolio' }
  ];

  if (user?.role === 'admin') {
    navItems.push({ to: '/admin/simulator', label: 'Simulator' });
  }

  return (
    <div className="min-h-screen bg-[radial-gradient(circle_at_top,_rgba(240,185,11,0.08),_transparent_30%),linear-gradient(180deg,_#07111f_0%,_#050b14_100%)]">
      <div className="grid min-h-screen grid-cols-1 lg:grid-cols-[260px_minmax(0,1fr)]">
        <aside className="border-b border-border/80 bg-panel/70 px-5 py-6 backdrop-blur lg:sticky lg:top-0 lg:h-screen lg:border-b-0 lg:border-r">
          <div className="mb-8">
            <div className="text-2xl font-black tracking-tight text-white">StonkExchange</div>
            <p className="mt-1 text-xs uppercase tracking-[0.3em] text-accent">Spot Market</p>
          </div>

          <nav className="space-y-2">
            {navItems.map((item) => (
              <NavLink
                key={item.to}
                to={item.to}
                className={({ isActive }) =>
                  `sidebar-link ${isActive ? 'sidebar-link-active' : ''}`
                }
              >
                <span>{item.label}</span>
              </NavLink>
            ))}
          </nav>
        </aside>

        <div className="flex min-w-0 flex-col">
          <header className="border-b border-border/80 bg-panel/60 px-4 py-4 backdrop-blur sm:px-6">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <p className="text-xs uppercase tracking-[0.25em] text-slate-400">Logged in as</p>
                <h1 className="text-lg font-semibold text-white">{user?.username || 'User'}</h1>
              </div>

              <div className="flex flex-wrap items-center gap-3">
                <div className="rounded-2xl border border-border bg-white/5 px-4 py-2 text-right">
                  <p className="text-[10px] uppercase tracking-[0.3em] text-slate-500">Balance</p>
                  <p className="text-sm font-semibold text-green">
                    ${Number(walletQuery.data?.cash_balance || 0).toFixed(2)}
                  </p>
                </div>
                <button
                  type="button"
                  onClick={logout}
                  className="rounded-xl border border-border bg-white/5 px-4 py-2 text-sm font-medium text-slate-200 transition hover:bg-white/10"
                >
                  Logout
                </button>
              </div>
            </div>
          </header>

          <main className="flex-1 min-w-0 p-4 sm:p-6">
            <Outlet />
          </main>
        </div>
      </div>
    </div>
  );
}
