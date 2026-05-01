import { useMemo } from 'react';
import { useQuery } from 'react-query';
import { fetchPortfolio, fetchWallet } from '../features/portfolio/portfolioService';
import { fetchStocks } from '../features/trading/tradingService';

function money(value) {
  return Number(value || 0).toFixed(2);
}

export default function PortfolioPage() {
  const walletQuery = useQuery({ queryKey: ['wallet'], queryFn: fetchWallet });
  const portfolioQuery = useQuery({ queryKey: ['portfolio'], queryFn: fetchPortfolio });
  const stocksQuery = useQuery({ queryKey: ['stocks'], queryFn: fetchStocks });

  const holdings = useMemo(() => {
    return (portfolioQuery.data || [])
      .filter((holding) => Number(holding.quantity || 0) > 0)
      .map((holding) => {
        const stock = (stocksQuery.data || []).find((item) => item.ticker === holding.ticker);
        const currentPrice = Number(stock?.last_price || 0);
        const currentValue = Number(holding.quantity || 0) * currentPrice;
        const costBasis = Number(holding.quantity || 0) * Number(holding.average_price || 0);
        const profitLoss = currentValue - costBasis;
        return {
          ...holding,
          currentPrice,
          currentValue,
          profitLoss
        };
      });
  }, [portfolioQuery.data, stocksQuery.data]);

  const availableBalance = Number(walletQuery.data?.cash_balance || 0);
  const reservedBalance = Number(walletQuery.data?.reserved_balance || 0);
  const holdingsValue = holdings.reduce((total, holding) => total + holding.currentValue, 0);
  const totalBalance = availableBalance + reservedBalance + holdingsValue;

  return (
    <section className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold text-white">Portfolio</h2>
        <p className="mt-1 text-sm text-slate-400">Balances, holdings, and live profit and loss.</p>
      </div>

      <div className="grid gap-6 md:grid-cols-3">
        <div className="glass-panel p-6">
          <p className="text-xs uppercase tracking-[0.2em] text-slate-500">Total Balance</p>
          <p className="mt-3 text-3xl font-bold text-white">${money(totalBalance)}</p>
        </div>
        <div className="glass-panel p-6">
          <p className="text-xs uppercase tracking-[0.2em] text-slate-500">Available Balance</p>
          <p className="mt-3 text-3xl font-bold text-white">${money(availableBalance)}</p>
        </div>
        <div className="glass-panel p-6">
          <p className="text-xs uppercase tracking-[0.2em] text-slate-500">Reserved + Holdings</p>
          <p className="mt-3 text-3xl font-bold text-white">${money(reservedBalance + holdingsValue)}</p>
        </div>
      </div>

      <div className="glass-panel overflow-hidden">
        <table className="min-w-full text-left text-sm">
          <thead className="border-b border-border bg-white/5 text-slate-400">
            <tr>
              <th className="px-5 py-4">Stock</th>
              <th className="px-5 py-4">Quantity</th>
              <th className="px-5 py-4">Avg Price</th>
              <th className="px-5 py-4">Current Value</th>
              <th className="px-5 py-4">Profit/Loss</th>
            </tr>
          </thead>
          <tbody>
            {holdings.length === 0 ? (
              <tr>
                <td className="px-5 py-8 text-slate-400" colSpan={5}>
                  No holdings yet.
                </td>
              </tr>
            ) : (
              holdings.map((row) => (
                <tr key={`${row.user_id}-${row.stock_id}`} className="border-b border-border/70">
                  <td className="px-5 py-4 font-semibold text-white">{row.ticker}</td>
                  <td className="px-5 py-4 text-slate-300">{Number(row.quantity || 0).toLocaleString()}</td>
                  <td className="px-5 py-4 text-slate-300">${money(row.average_price)}</td>
                  <td className="px-5 py-4 text-slate-300">${money(row.currentValue)}</td>
                  <td className={`px-5 py-4 font-semibold ${row.profitLoss >= 0 ? 'text-green' : 'text-red'}`}>
                    ${money(row.profitLoss)}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </section>
  );
}
