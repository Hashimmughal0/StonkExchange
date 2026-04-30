import { useQuery } from 'react-query';
import api from '../services/api';

async function fetchSimulatorOrders() {
  const { data } = await api.get('/admin/simulator-orders', { params: { limit: 50 } });
  return data.data;
}

export default function AdminSimulatorPage() {
  const { data, isLoading, error } = useQuery({
    queryKey: ['admin-simulator-orders'],
    queryFn: fetchSimulatorOrders,
    refetchInterval: 5_000
  });

  return (
    <section className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold text-white">Simulator Orders</h2>
        <p className="mt-1 text-sm text-slate-400">Latest liquidity bot buy/sell orders from the database.</p>
      </div>

      <div className="glass-panel overflow-hidden">
        <table className="min-w-full text-left text-sm">
          <thead className="border-b border-border bg-white/5 text-slate-400">
            <tr>
              <th className="px-5 py-4">Bot</th>
              <th className="px-5 py-4">Side</th>
              <th className="px-5 py-4">Type</th>
              <th className="px-5 py-4">Qty</th>
              <th className="px-5 py-4">Filled</th>
              <th className="px-5 py-4">Price</th>
              <th className="px-5 py-4">Status</th>
              <th className="px-5 py-4">Created</th>
            </tr>
          </thead>
          <tbody>
            {isLoading ? (
              <tr>
                <td className="px-5 py-6 text-slate-400" colSpan={8}>
                  Loading simulator orders...
                </td>
              </tr>
            ) : error ? (
              <tr>
                <td className="px-5 py-6 text-red" colSpan={8}>
                  Failed to load simulator orders.
                </td>
              </tr>
            ) : (data || []).length === 0 ? (
              <tr>
                <td className="px-5 py-6 text-slate-400" colSpan={8}>
                  No simulator orders yet.
                </td>
              </tr>
            ) : (
              (data || []).map((row) => (
                <tr key={row.order_id} className="border-b border-border/70">
                  <td className="px-5 py-4 text-white">{row.username}</td>
                  <td className={`px-5 py-4 font-semibold ${row.side === 'buy' ? 'text-green' : 'text-red'}`}>
                    {row.side}
                  </td>
                  <td className="px-5 py-4 text-slate-300">{row.order_type}</td>
                  <td className="px-5 py-4 text-slate-300">{row.quantity}</td>
                  <td className="px-5 py-4 text-slate-300">{row.filled_quantity}</td>
                  <td className="px-5 py-4 text-slate-300">${Number(row.limit_price || 0).toFixed(2)}</td>
                  <td className="px-5 py-4 text-slate-300">{row.status}</td>
                  <td className="px-5 py-4 text-slate-400">{new Date(row.created_at).toLocaleString()}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </section>
  );
}
