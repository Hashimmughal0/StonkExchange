import { useState } from 'react';
import { useMutation, useQuery } from 'react-query';
import { fetchOrderBook, fetchStock, fetchTrades, placeOrder } from '../features/trading/tradingService';

export default function TradePage() {
  const [ticker, setTicker] = useState('AAPL');
  const [form, setForm] = useState({
    orderType: 'limit',
    side: 'buy',
    quantity: 1,
    limitPrice: 0,
    stopPrice: ''
  });

  const stockQuery = useQuery({
    queryKey: ['stock', ticker],
    queryFn: () => fetchStock(ticker)
  });
  const orderBookQuery = useQuery({
    queryKey: ['orderbook', ticker],
    queryFn: () => fetchOrderBook(ticker)
  });
  const tradesQuery = useQuery({
    queryKey: ['trades', ticker],
    queryFn: () => fetchTrades(ticker)
  });

  const orderMutation = useMutation({
    mutationFn: placeOrder
  });

  const estimatedPrice = Number(
    form.orderType === 'market' ? stockQuery.data?.last_price || 0 : form.limitPrice || 0
  );

  return (
    <section className="grid gap-6 xl:grid-cols-[minmax(0,1.2fr)_minmax(320px,0.8fr)]">
      <div className="min-w-0 space-y-6">
        <div className="glass-panel p-6">
          <div className="flex flex-wrap items-center gap-3">
            <input
              className="rounded-xl border border-border bg-panel2 px-4 py-3 text-sm outline-none focus:border-accent"
              value={ticker}
              onChange={(e) => setTicker(e.target.value.toUpperCase())}
              placeholder="Ticker"
            />
            <div>
              <h2 className="text-2xl font-bold text-white">{stockQuery.data?.ticker || ticker}</h2>
              <p className="text-sm text-slate-400">{stockQuery.data?.company_name || 'Select a market'}</p>
            </div>
          </div>
          <div className="mt-6 grid gap-4 md:grid-cols-3">
            <div className="rounded-2xl border border-border bg-white/5 p-4">
              <p className="text-xs uppercase tracking-[0.2em] text-slate-500">Last Price</p>
              <p className="mt-2 text-2xl font-bold text-green">${Number(stockQuery.data?.last_price || 0).toFixed(2)}</p>
            </div>
            <div className="rounded-2xl border border-border bg-white/5 p-4">
              <p className="text-xs uppercase tracking-[0.2em] text-slate-500">Order Book</p>
              <p className="mt-2 text-2xl font-bold text-white">{orderBookQuery.data?.length || 0}</p>
            </div>
            <div className="rounded-2xl border border-border bg-white/5 p-4">
              <p className="text-xs uppercase tracking-[0.2em] text-slate-500">Recent Trades</p>
              <p className="mt-2 text-2xl font-bold text-white">{tradesQuery.data?.length || 0}</p>
            </div>
          </div>
        </div>

        <div className="glass-panel p-6">
          <h3 className="text-lg font-semibold text-white">Recent Trades</h3>
          <div className="mt-4 max-h-80 space-y-3 overflow-auto pr-1">
            {(tradesQuery.data || []).length === 0 ? (
              <p className="text-sm text-slate-400">No trades yet.</p>
            ) : (tradesQuery.data || []).slice(0, 8).map((trade) => (
              <div key={trade.trade_id} className="flex items-center justify-between rounded-xl border border-border bg-white/5 px-4 py-3">
                <span className="font-medium text-white">{trade.ticker}</span>
                <span className="text-slate-300">{trade.quantity} @ ${Number(trade.price).toFixed(2)}</span>
                <span className="text-xs text-slate-500">{new Date(trade.executed_at).toLocaleString()}</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      <div className="min-w-0 space-y-6">
        <div className="glass-panel p-6">
          <h3 className="text-lg font-semibold text-white">Place Order</h3>
          <form
            className="mt-4 space-y-4"
            onSubmit={(e) => {
              e.preventDefault();
              orderMutation.mutate({
                ticker,
                side: form.side,
                orderType: form.orderType,
                quantity: Number(form.quantity),
                limitPrice: form.orderType === 'market' ? undefined : Number(form.limitPrice),
                stopPrice: form.orderType === 'stop_loss' ? Number(form.stopPrice || 0) : undefined
              });
            }}
          >
            <select
              className="w-full rounded-xl border border-border bg-panel2 px-4 py-3 text-sm"
              value={form.orderType}
              onChange={(e) => setForm({ ...form, orderType: e.target.value })}
            >
              <option value="market">Market</option>
              <option value="limit">Limit</option>
              <option value="stop_loss">Stop Loss</option>
            </select>
            <select
              className="w-full rounded-xl border border-border bg-panel2 px-4 py-3 text-sm"
              value={form.side}
              onChange={(e) => setForm({ ...form, side: e.target.value })}
            >
              <option value="buy">Buy</option>
              <option value="sell">Sell</option>
            </select>
            <input
              className="w-full rounded-xl border border-border bg-panel2 px-4 py-3 text-sm"
              type="number"
              min="1"
              value={form.quantity}
              onChange={(e) => setForm({ ...form, quantity: Number(e.target.value) })}
              placeholder="Quantity"
            />
            {form.orderType === 'limit' ? (
              <input
                className="w-full rounded-xl border border-border bg-panel2 px-4 py-3 text-sm"
                type="number"
                step="0.01"
                value={form.limitPrice}
                onChange={(e) => setForm({ ...form, limitPrice: e.target.value })}
                placeholder="Limit Price"
              />
            ) : null}
            {form.orderType === 'stop_loss' ? (
              <input
                className="w-full rounded-xl border border-border bg-panel2 px-4 py-3 text-sm"
                type="number"
                step="0.01"
                value={form.stopPrice}
                onChange={(e) => setForm({ ...form, stopPrice: e.target.value })}
                placeholder="Stop Price"
              />
            ) : null}
            <div className="rounded-2xl border border-border bg-white/5 p-4 text-sm text-slate-300">
              <div className="flex items-center justify-between">
                <span>Reference price</span>
                <span className="font-semibold text-white">${estimatedPrice.toFixed(2)}</span>
              </div>
            </div>
            <button
              type="submit"
              className="w-full rounded-xl bg-accent px-4 py-3 text-sm font-semibold text-slate-950 transition hover:bg-accent2"
            >
              {orderMutation.isLoading ? 'Submitting...' : 'Submit Order'}
            </button>
            {orderMutation.isSuccess ? (
              <p className="text-sm text-green">Order submitted successfully.</p>
            ) : null}
            {orderMutation.isError ? (
              <p className="text-sm text-red">{orderMutation.error?.response?.data?.message || 'Order failed'}</p>
            ) : null}
          </form>
        </div>
      </div>
    </section>
  );
}
