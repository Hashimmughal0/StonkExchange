import { useMemo, useState } from 'react';
import { useMutation, useQueryClient } from 'react-query';
import { placeOrder } from '../../features/trading/tradingService';

function money(value) {
  return Number(value || 0).toFixed(2);
}

export default function OrderPanel({
  ticker,
  lastPrice,
  availableBalance,
  ownedQuantity = 0,
  onSuccess
}) {
  const queryClient = useQueryClient();
  const [form, setForm] = useState({
    side: 'buy',
    orderType: 'market',
    quantity: 1,
    limitPrice: '',
    stopPrice: ''
  });

  const estimatedPrice = Number(form.orderType === 'market' ? lastPrice : form.limitPrice || 0);
  const estimatedCost = Number(form.quantity || 0) * estimatedPrice;
  const fees = estimatedCost * 0.001;
  const totalCost = estimatedCost + fees;
  const sellValue = Number(form.quantity || 0) * estimatedPrice;

  const validationError = useMemo(() => {
    if (!ticker) {
      return 'Missing ticker';
    }
    if (Number(form.quantity) <= 0) {
      return 'Quantity must be greater than zero';
    }
    if (form.orderType === 'limit' && Number(form.limitPrice) <= 0) {
      return 'Limit price is required for limit orders';
    }
    if (form.side === 'buy' && totalCost > Number(availableBalance || 0)) {
      return 'Insufficient balance';
    }
    if (form.side === 'sell' && Number(form.quantity) > Number(ownedQuantity || 0)) {
      return 'Cannot sell more than owned';
    }
    return '';
  }, [availableBalance, form.limitPrice, form.orderType, form.quantity, form.side, ownedQuantity, ticker, totalCost]);

  const mutation = useMutation({
    mutationFn: placeOrder,
    onSuccess: async (data) => {
      await Promise.all([
        queryClient.invalidateQueries(),
        queryClient.invalidateQueries({ queryKey: ['stock-detail', ticker] }),
        queryClient.invalidateQueries({ queryKey: ['stock-orderbook', ticker] }),
        queryClient.invalidateQueries({ queryKey: ['stock-trades', ticker] }),
        queryClient.invalidateQueries({ queryKey: ['wallet'] }),
        queryClient.invalidateQueries({ queryKey: ['portfolio'] }),
        queryClient.invalidateQueries({ queryKey: ['stocks'] })
      ]);
      if (onSuccess) onSuccess(data);
    }
  });

  return (
    <div className="glass-panel p-6">
      <h3 className="text-lg font-semibold text-white">Trade Panel</h3>
      <p className="mt-1 text-sm text-slate-400">Place orders for {ticker}.</p>

      <form
        className="mt-4 space-y-4"
        onSubmit={(e) => {
          e.preventDefault();
          if (validationError) return;
          mutation.mutate({
            ticker,
            side: form.side,
            orderType: form.orderType,
            quantity: Number(form.quantity),
            limitPrice: form.orderType === 'market' ? undefined : Number(form.limitPrice),
            stopPrice: form.orderType === 'stop_loss' ? Number(form.stopPrice || 0) : undefined
          });
        }}
      >
        <div className="grid grid-cols-2 gap-3">
          <button
            type="button"
            onClick={() => setForm({ ...form, side: 'buy' })}
            className={`rounded-xl px-4 py-3 text-sm font-semibold transition ${
              form.side === 'buy' ? 'bg-green text-slate-950' : 'bg-white/5 text-slate-300'
            }`}
          >
            Buy
          </button>
          <button
            type="button"
            onClick={() => setForm({ ...form, side: 'sell' })}
            className={`rounded-xl px-4 py-3 text-sm font-semibold transition ${
              form.side === 'sell' ? 'bg-red text-white' : 'bg-white/5 text-slate-300'
            }`}
          >
            Sell
          </button>
        </div>

        <select
          className="w-full rounded-xl border border-border bg-panel2 px-4 py-3 text-sm outline-none"
          value={form.orderType}
          onChange={(e) => setForm({ ...form, orderType: e.target.value })}
        >
          <option value="market">Market</option>
          <option value="limit">Limit</option>
        </select>

        <input
          className="w-full rounded-xl border border-border bg-panel2 px-4 py-3 text-sm outline-none"
          type="number"
          min="1"
          value={form.quantity}
          onChange={(e) => setForm({ ...form, quantity: Number(e.target.value) })}
          placeholder="Quantity"
        />

        {form.orderType === 'limit' ? (
          <input
            className="w-full rounded-xl border border-border bg-panel2 px-4 py-3 text-sm outline-none"
            type="number"
            step="0.01"
            value={form.limitPrice}
            onChange={(e) => setForm({ ...form, limitPrice: e.target.value })}
            placeholder="Limit Price"
          />
        ) : null}

        <div className="rounded-2xl border border-border bg-white/5 p-4 text-sm text-slate-300">
          <div className="flex items-center justify-between">
            <span>Estimated cost</span>
            <span className="font-semibold text-white">${money(form.side === 'buy' ? estimatedCost : sellValue)}</span>
          </div>
          <div className="mt-2 flex items-center justify-between">
            <span>Fees</span>
            <span className="font-semibold text-white">${money(fees)}</span>
          </div>
          <div className="mt-2 flex items-center justify-between border-t border-border pt-2">
            <span>Total</span>
            <span className="font-semibold text-white">${money(form.side === 'buy' ? totalCost : sellValue - fees)}</span>
          </div>
        </div>

        {validationError ? <p className="text-sm text-red">{validationError}</p> : null}
        {mutation.isError ? (
          <p className="text-sm text-red">{mutation.error?.response?.data?.message || 'Order failed'}</p>
        ) : null}
        {mutation.isSuccess ? <p className="text-sm text-green">Order submitted successfully.</p> : null}

        <button
          type="submit"
          className="w-full rounded-xl bg-accent px-4 py-3 text-sm font-semibold text-white transition hover:bg-accent2 disabled:opacity-60"
          disabled={mutation.isLoading || Boolean(validationError)}
        >
          {mutation.isLoading ? 'Submitting...' : 'Submit Order'}
        </button>
      </form>
    </div>
  );
}
