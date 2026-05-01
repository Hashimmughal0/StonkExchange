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
import HomePage from './pages/HomePage';
import { useAuthStore } from './store/authStore';

export default function App() {
  const token = useAuthStore((state) => state.token);
  const user = useAuthStore((state) => state.user);

  return (
    <Routes>
      <Route path="/" element={<HomePage />} />
      <Route path="/login" element={token ? <Navigate to="/markets" replace /> : <LoginPage />} />
      <Route path="/register" element={token ? <Navigate to="/markets" replace /> : <RegisterPage />} />
      <Route
        element={
          <ProtectedRoute>
            <AppShell />
          </ProtectedRoute>
        }
      >
        <Route path="/markets" element={<MarketsPage />} />
        <Route path="/markets/:ticker" element={<StockDetailPage />} />
        <Route path="/orders" element={<OrdersPage />} />
        <Route path="/portfolio" element={<PortfolioPage />} />
        {user?.role === 'admin' ? <Route path="/admin/simulator" element={<AdminSimulatorPage />} /> : null}
      </Route>
      <Route path="*" element={<Navigate to={token ? '/markets' : '/'} replace />} />
    </Routes>
  );
}
