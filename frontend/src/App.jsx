import { Navigate, Route, Routes } from 'react-router-dom';
import AppShell from './components/layout/AppShell';
import ProtectedRoute from './components/layout/ProtectedRoute';
import LoginPage from './pages/LoginPage';
import MarketsPage from './pages/MarketsPage';
import RegisterPage from './pages/RegisterPage';
import OrdersPage from './pages/OrdersPage';
import AdminSimulatorPage from './pages/AdminSimulatorPage';
import StockDetailPage from './pages/StockDetailPage';
import PortfolioPage from './pages/PortfolioPage';
import TradePage from './pages/TradePage';
import { useAuthStore } from './store/authStore';

export default function App() {
  const token = useAuthStore((state) => state.token);
  const user = useAuthStore((state) => state.user);

  return (
    <Routes>
      <Route path="/login" element={token ? <Navigate to="/" replace /> : <LoginPage />} />
      <Route path="/register" element={token ? <Navigate to="/" replace /> : <RegisterPage />} />
      <Route
        path="/"
        element={
          <ProtectedRoute>
            <AppShell />
          </ProtectedRoute>
        }
      >
        <Route index element={<Navigate to="/markets" replace />} />
        <Route path="markets" element={<MarketsPage />} />
        <Route path="markets/:ticker" element={<StockDetailPage />} />
        <Route path="trade" element={<TradePage />} />
        <Route path="orders" element={<OrdersPage />} />
        <Route path="portfolio" element={<PortfolioPage />} />
        {user?.role === 'admin' ? <Route path="admin/simulator" element={<AdminSimulatorPage />} /> : null}
      </Route>
      <Route path="*" element={<Navigate to={token ? '/markets' : '/login'} replace />} />
    </Routes>
  );
}
