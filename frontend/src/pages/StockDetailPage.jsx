import { useMemo, useState } from 'react';
import { useQuery } from 'react-query';
import { useNavigate, useParams } from 'react-router-dom';
import PriceChart from '../components/charts/PriceChart';
import OrderPanel from '../components/trading/OrderPanel';
import { fetchOrderBook, fetchPriceSeries, fetchStock, fetchTrades } from '../features/trading/tradingService';
import { fetchPortfolio, fetchWallet } from '../features/portfolio/portfolioService';

const TIMEFRAMES = [
  { label: '1m', limit: 30, refetch: 15_000 },
  { label: '5m', limit: 60, refetch: 20_000 },
  { label: '1h', limit: 120, refetch: 30_000 },
  { label: '1d', limit: 240, refetch: 60_000 }
];

export default function StockDetailPage() {
  const { ticker } = useParams();
  const navigate = useNavigate();
  const [timeframe, setTimeframe] = useState(TIMEFRAMES[1]);

  const stockQuery = useQuery({
    queryKey: ['stock-detail', ticker],
    queryFn: () => fetchStock(ticker),
    refetchInterval: timeframe.refetch
  });

  const chartQuery = useQuery({
    queryKey: ['stock-chart', ticker, timeframe.label],
    queryFn: () => fetchPriceSeries(ticker, timeframe.limit),
    refetchInterval: timeframe.refetch
  });

  const orderBookQuery = useQuery({
    queryKey: ['stock-orderbook', ticker],
    queryFn: () => fetchOrderBook(ticker),
    refetchInterval: 15_000
  });

  const tradesQuery = useQuery({
    queryKey: ['stock-trades', ticker],
    queryFn: () => fetchTrades(ticker),
    refetchInterval: 15_000
  });
  const walletQuery = useQuery({ queryKey: ['wallet'], queryFn: fetchWallet });
  const portfolioQuery = useQuery({ queryKey: ['portfolio'], queryFn: fetchPortfolio });

  const latest = useMemo(() => {
    const data = chartQuery.data || [];
    return data[data.length - 1] || null;
  }, [chartQuery.data]);

  const bestBid = useMemo(
    () =>
      (orderBookQuery.data || [])
        .filter((row) => row.side === 'buy')
        .sort((a, b) => Number(b.limit_price) - Number(a.limit_price))[0],
    [orderBookQuery.data]
  );

  const bestAsk = useMemo(
    () =>
      (orderBookQuery.data || [])
        .filter((row) => row.side === 'sell')
        .sort((a, b) => Number(a.limit_price) - Number(b.limit_price))[0],
    [orderBookQuery.data]
  );

  const ownedQuantity = useMemo(() => {
    const holdings = portfolioQuery.data || [];
    const match = holdings.find((row) => row.ticker === ticker);
    return Number(match?.quantity || 0);
  }, [portfolioQuery.data, ticker]);

  return (
    <section className="grid gap-6 xl:grid-cols-[minmax(0,1.35fr)_minmax(320px,0.75fr)]">
      <div className="min-w-0 space-y-6">
        <button
          type="button"
          onClick={() => navigate('/markets')}
          className="text-sm text-slate-400 transition hover:text-white"
        >
          Back to markets
        </button>

        <div className="glass-panel p-6">
          <div className="flex flex-wrap items-end justify-between gap-4">
            <div>
              <p className="text-xs uppercase tracking-[0.25em] text-accent">Market detail</p>
              <h1 className="mt-2 text-3xl font-bold text-white">{stockQuery.data?.ticker || ticker}</h1>
              <p className="mt-1 text-sm text-slate-400">{stockQuery.data?.company_name}</p>
            </div>
            <div className="grid gap-3 sm:grid-cols-3">
              <div className="rounded-2xl border border-border bg-white/5 px-4 py-3">
                <p className="text-xs uppercase tracking-[0.2em] text-slate-500">Last</p>
                <p className="mt-2 text-lg font-semibold text-white">
                  ${Number(stockQuery.data?.last_price || 0).toFixed(2)}
                </p>
              </div>
              <div className="rounded-2xl border border-border bg-white/5 px-4 py-3">
                <p className="text-xs uppercase tracking-[0.2em] text-slate-500">Best Bid</p>
                <p className="mt-2 text-lg font-semibold text-green">
                  ${Number(bestBid?.limit_price || 0).toFixed(2)}
                </p>
              </div>
              <div className="rounded-2xl border border-border bg-white/5 px-4 py-3">
                <p className="text-xs uppercase tracking-[0.2em] text-slate-500">Best Ask</p>
                <p className="mt-2 text-lg font-semibold text-red">
                  ${Number(bestAsk?.limit_price || 0).toFixed(2)}
                </p>
              </div>
            </div>
          </div>
        </div>

        <div className="glass-panel p-4">
          <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
            <div className="flex gap-2">
              {TIMEFRAMES.map((item) => (
                <button
                  key={item.label}
                  type="button"
                  onClick={() => setTimeframe(item)}
                  className={`rounded-xl px-4 py-2 text-sm font-medium transition ${
                    item.label === timeframe.label
                      ? 'bg-accent text-slate-950'
                      : 'bg-white/5 text-slate-300 hover:bg-white/10'
                  }`}
                >
                  {item.label}
                </button>
              ))}
            </div>
            <p className="text-xs uppercase tracking-[0.2em] text-slate-500">
              Live refresh {Math.round(timeframe.refetch / 1000)}s
            </p>
          </div>
          <PriceChart data={chartQuery.data || []} />
        </div>

        <div className="grid gap-6 lg:grid-cols-2">
          <div className="glass-panel p-6">
            <h3 className="text-lg font-semibold text-white">Order Book</h3>
            <div className="mt-4 max-h-80 space-y-3 overflow-auto pr-1">
              {(orderBookQuery.data || []).length === 0 ? (
                <p className="text-sm text-slate-400">No order book data yet.</p>
              ) : (orderBookQuery.data || []).slice(0, 10).map((row, index) => (
                <div
                  key={`${row.side}-${row.limit_price}-${index}`}
                  className="flex items-center justify-between rounded-xl border border-border bg-white/5 px-4 py-3"
                >
                  <span className={`font-medium ${row.side === 'buy' ? 'text-green' : 'text-red'}`}>
                    {row.side.toUpperCase()}
                  </span>
                  <span className="text-slate-300">${Number(row.limit_price || 0).toFixed(2)}</span>
                  <span className="text-slate-400">{Number(row.total_quantity || 0).toLocaleString()}</span>
                </div>
              ))}
            </div>
          </div>

          <div className="glass-panel p-6">
            <h3 className="text-lg font-semibold text-white">Trade History</h3>
            <div className="mt-4 max-h-80 space-y-3 overflow-auto pr-1">
              {(tradesQuery.data || []).length === 0 ? (
                <p className="text-sm text-slate-400">No trades yet.</p>
              ) : (tradesQuery.data || []).slice(0, 8).map((trade) => (
                <div
                  key={trade.trade_id}
                  className="flex items-center justify-between rounded-xl border border-border bg-white/5 px-4 py-3"
                >
                  <span className="font-medium text-white">{trade.ticker}</span>
                  <span className="text-slate-300">{trade.quantity} @ ${Number(trade.price).toFixed(2)}</span>
                  <span className="text-xs text-slate-500">
                    {new Date(trade.executed_at).toLocaleTimeString([], {
                      hour: '2-digit',
                      minute: '2-digit'
                    })}
                  </span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>

      <aside className="min-w-0 space-y-6">
        <OrderPanel
          ticker={ticker}
          lastPrice={stockQuery.data?.last_price || latest?.close_price || 0}
          availableBalance={walletQuery.data?.cash_balance || 0}
          ownedQuantity={ownedQuantity}
        />

        <div className="glass-panel p-6">
          <h3 className="text-lg font-semibold text-white">Live Price</h3>
          <p className="mt-2 text-3xl font-bold text-green">
            ${Number(stockQuery.data?.last_price || latest?.close_price || 0).toFixed(2)}
          </p>
          <p className="mt-2 text-sm text-slate-400">
            Updates every {Math.round(timeframe.refetch / 1000)} seconds while the page is open.
          </p>
        </div>
      </aside>
    </section>
  );
}
