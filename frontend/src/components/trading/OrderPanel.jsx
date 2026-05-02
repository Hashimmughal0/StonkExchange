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
    quantity: 0,
    limitPrice: '',
    stopPrice: ''
  });

  const estimatedPrice = Number(form.orderType === 'market' ? lastPrice : form.limitPrice || 0);
  const estimatedCost = Number(form.quantity || 0) * estimatedPrice;
  const fees = estimatedCost * 0.001;
  const totalCost = estimatedCost + fees;
  const sellValue = Number(form.quantity || 0) * estimatedPrice;

  const currentPercent = useMemo(() => {
    if (form.side === 'buy') {
       if (!availableBalance || !estimatedPrice) return 0;
       const maxQty = Math.floor(availableBalance / estimatedPrice);
       if (maxQty === 0) return 0;
       return Math.min(100, Math.max(0, Math.round((form.quantity / maxQty) * 100)));
    } else {
       if (!ownedQuantity) return 0;
       return Math.min(100, Math.max(0, Math.round((form.quantity / ownedQuantity) * 100)));
    }
  }, [form.side, form.quantity, availableBalance, estimatedPrice, ownedQuantity]);

  const handlePercentClick = (percent) => {
    if (form.side === 'buy') {
      const maxQty = estimatedPrice > 0 ? Math.floor((availableBalance / estimatedPrice) * (percent / 100)) : 0;
      setForm(prev => ({ ...prev, quantity: maxQty }));
    } else {
      const maxQty = Math.floor(ownedQuantity * (percent / 100));
      setForm(prev => ({ ...prev, quantity: maxQty }));
    }
  };

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
      setForm(prev => ({ ...prev, quantity: 0 }));
      if (onSuccess) onSuccess(data);
    }
  });

  return (
    <div className="glass-panel p-6">
      <div className="flex flex-col gap-1">
        <h3 className="text-lg font-semibold text-white">Trade {ticker}</h3>
        <div className="flex items-center justify-between text-xs text-slate-400">
          <span>{form.side === 'buy' ? 'Avail Balance:' : 'Avail Quantity:'}</span>
          <span className="font-medium text-slate-300">
            {form.side === 'buy' ? `$${money(availableBalance)}` : `${Number(ownedQuantity).toLocaleString()} ${ticker}`}
          </span>
        </div>
      </div>

      <form
        className="mt-5 space-y-5"
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
        <div className="flex rounded-xl bg-panel2 p-1 border border-border">
          <button
            type="button"
            onClick={() => setForm({ ...form, side: 'buy' })}
            className={`flex-1 rounded-lg py-2 text-sm font-semibold transition ${
              form.side === 'buy' ? 'bg-green text-slate-950 shadow-sm' : 'text-slate-400 hover:text-slate-300'
            }`}
          >
            Buy
          </button>
          <button
            type="button"
            onClick={() => setForm({ ...form, side: 'sell' })}
            className={`flex-1 rounded-lg py-2 text-sm font-semibold transition ${
              form.side === 'sell' ? 'bg-red text-white shadow-sm' : 'text-slate-400 hover:text-slate-300'
            }`}
          >
            Sell
          </button>
        </div>

        <div className="flex rounded-xl bg-panel2 p-1 border border-border">
          <button
            type="button"
            onClick={() => setForm({ ...form, orderType: 'market' })}
            className={`flex-1 rounded-lg py-1.5 text-xs font-medium transition ${
              form.orderType === 'market' ? 'bg-white/10 text-white' : 'text-slate-400 hover:text-slate-300'
            }`}
          >
            Market
          </button>
          <button
            type="button"
            onClick={() => setForm({ ...form, orderType: 'limit' })}
            className={`flex-1 rounded-lg py-1.5 text-xs font-medium transition ${
              form.orderType === 'limit' ? 'bg-white/10 text-white' : 'text-slate-400 hover:text-slate-300'
            }`}
          >
            Limit
          </button>
        </div>

        <div className="space-y-3">
          {form.orderType === 'limit' ? (
            <div className="flex items-center rounded-xl border border-border bg-panel2 px-4 py-3 transition focus-within:border-accent">
              <span className="w-16 text-sm text-slate-500">Price</span>
              <input
                className="flex-1 bg-transparent text-right text-sm text-white outline-none [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
                type="number"
                step="0.01"
                min="0"
                value={form.limitPrice}
                onChange={(e) => setForm({ ...form, limitPrice: e.target.value })}
                placeholder="0.00"
              />
              <span className="ml-3 text-sm font-medium text-slate-400">USD</span>
            </div>
          ) : (
            <div className="flex items-center rounded-xl border border-border bg-panel2 px-4 py-3 opacity-60">
              <span className="w-16 text-sm text-slate-500">Price</span>
              <input
                className="flex-1 bg-transparent text-right text-sm text-white outline-none cursor-not-allowed"
                type="text"
                readOnly
                value="Market"
              />
              <span className="ml-3 text-sm font-medium text-slate-400">USD</span>
            </div>
          )}

          <div className="flex items-center rounded-xl border border-border bg-panel2 px-4 py-3 transition focus-within:border-accent">
            <span className="w-16 text-sm text-slate-500">Amount</span>
            <input
              className="flex-1 bg-transparent text-right text-sm text-white outline-none [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
              type="number"
              min="0"
              step="1"
              value={form.quantity || ''}
              onChange={(e) => setForm({ ...form, quantity: Number(e.target.value) })}
              placeholder="0"
            />
            <span className="ml-3 text-sm font-medium text-slate-400">{ticker}</span>
          </div>

          <div className="px-1 pt-1 pb-2">
            <input
              type="range"
              min="0"
              max="100"
              value={currentPercent || 0}
              onChange={(e) => handlePercentClick(Number(e.target.value))}
              className="w-full accent-accent h-1.5 bg-white/10 rounded-lg appearance-none cursor-pointer"
            />
            <div className="mt-3 flex justify-between gap-2">
              {[25, 50, 75, 100].map(pct => (
                <button
                  key={pct}
                  type="button"
                  onClick={() => handlePercentClick(pct)}
                  className="flex-1 rounded-md border border-border bg-white/5 py-1 text-[11px] font-medium text-slate-400 transition hover:bg-white/10 hover:text-white"
                >
                  {pct}%
                </button>
              ))}
            </div>
          </div>

          <div className="flex items-center rounded-xl border border-border bg-panel2 px-4 py-3 opacity-60">
            <span className="w-16 text-sm text-slate-500">Total</span>
            <input
              className="flex-1 bg-transparent text-right text-sm text-white outline-none cursor-not-allowed"
              type="text"
              readOnly
              value={money(form.side === 'buy' ? estimatedCost : sellValue)}
            />
            <span className="ml-3 text-sm font-medium text-slate-400">USD</span>
          </div>
        </div>

        <div className="rounded-2xl border border-border bg-white/5 p-4 text-xs text-slate-400">
          <div className="flex items-center justify-between">
            <span>Fees (0.1%)</span>
            <span className="text-slate-300">${money(fees)}</span>
          </div>
          <div className="mt-2 flex items-center justify-between border-t border-border/50 pt-2 font-medium">
            <span className="text-slate-300">Total {form.side === 'buy' ? 'Cost' : 'Return'}</span>
            <span className="text-white">${money(form.side === 'buy' ? totalCost : sellValue - fees)}</span>
          </div>
        </div>

        {validationError ? <p className="text-sm text-red font-medium">{validationError}</p> : null}
        {mutation.isError ? (
          <p className="text-sm text-red font-medium">{mutation.error?.response?.data?.message || 'Order failed'}</p>
        ) : null}
        {mutation.isSuccess ? <p className="text-sm text-green font-medium">Order submitted successfully.</p> : null}

        <button
          type="submit"
          className={`w-full rounded-xl px-4 py-3.5 text-sm font-bold text-white transition disabled:opacity-50 ${
            form.side === 'buy' ? 'bg-green hover:bg-green/90 text-slate-950' : 'bg-red hover:bg-red/90'
          }`}
          disabled={mutation.isLoading || Boolean(validationError) || form.quantity <= 0}
        >
          {mutation.isLoading ? 'Submitting...' : `${form.side === 'buy' ? 'Buy' : 'Sell'} ${ticker}`}
        </button>
      </form>
    </div>
  );
}
