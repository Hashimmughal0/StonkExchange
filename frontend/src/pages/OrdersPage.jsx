import { useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from 'react-query';
import OrdersTable from '../components/orders/OrdersTable';
import { cancelOrder, fetchOrders } from '../features/trading/tradingService';
import { useAuthStore } from '../store/authStore';

export default function OrdersPage() {
  const [filter, setFilter] = useState('open');
  const queryClient = useQueryClient();
  const token = useAuthStore((state) => state.token);

  const ordersQuery = useQuery({
    queryKey: ['orders', token],
    queryFn: fetchOrders,
    refetchInterval: 2_000
  });

  const cancelMutation = useMutation({
    mutationFn: cancelOrder,
    onSuccess: async () => {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ['orders', token] }),
        queryClient.invalidateQueries({ queryKey: ['wallet', token] }),
        queryClient.invalidateQueries({ queryKey: ['portfolio', token] })
      ]);
    }
  });

  const handleCancel = (orderId) => {
    cancelMutation.mutate(orderId);
  };

  const rows = useMemo(() => {
    const orders = ordersQuery.data || [];
    if (filter === 'completed') {
      return orders.filter((order) => ['filled', 'cancelled'].includes(String(order.status).toLowerCase()));
    }
    return orders.filter((order) => !['filled', 'cancelled'].includes(String(order.status).toLowerCase()));
  }, [filter, ordersQuery.data]);

  return (
    <section className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-2xl font-bold text-white">Order History</h2>
          <p className="mt-1 text-sm text-slate-400">Open and completed exchange orders.</p>
        </div>

        <div className="flex gap-2">
          <button
            type="button"
            onClick={() => setFilter('open')}
            className={`rounded-xl px-4 py-2 text-sm font-medium transition ${
              filter === 'open' ? 'bg-accent text-slate-950' : 'bg-white/5 text-slate-300 hover:bg-white/10'
            }`}
          >
            Open Orders
          </button>
          <button
            type="button"
            onClick={() => setFilter('completed')}
            className={`rounded-xl px-4 py-2 text-sm font-medium transition ${
              filter === 'completed' ? 'bg-accent text-slate-950' : 'bg-white/5 text-slate-300 hover:bg-white/10'
            }`}
          >
            Completed Orders
          </button>
        </div>
      </div>

      <OrdersTable rows={rows} onCancel={handleCancel} cancelDisabled={cancelMutation.isLoading} />
    </section>
  );
}
