import { useMemo, useState } from 'react';
import { useQueries, useQuery } from 'react-query';
import { useNavigate } from 'react-router-dom';
import MarketsTable from '../components/markets/MarketsTable';
import { fetchPriceChart, fetchStocks } from '../features/trading/tradingService';

function summarizeChart(chart = []) {
  if (!chart.length) {
    return { change_pct: 0, volume_24h: 0 };
  }
  const first = chart[0];
  const last = chart[chart.length - 1];
  const change_pct = first?.close_price
    ? ((Number(last.close_price) - Number(first.close_price)) / Number(first.close_price)) * 100
    : 0;
  const volume_24h = chart.reduce((total, candle) => total + Number(candle.volume || 0), 0);
  return { change_pct, volume_24h };
}

export default function MarketsPage() {
  const navigate = useNavigate();
  const [search, setSearch] = useState('');
  const [sortKey, setSortKey] = useState('volume_24h');
  const [filter, setFilter] = useState('all');

  const stocksQuery = useQuery({
    queryKey: ['stocks'],
    queryFn: fetchStocks,
    refetchInterval: 15_000
  });

  const filteredStocks = useMemo(() => {
    const rows = stocksQuery.data || [];
    const term = search.trim().toLowerCase();
    return rows.filter((row) => {
      const matchesSearch =
        !term ||
        row.ticker.toLowerCase().includes(term) ||
        row.company_name.toLowerCase().includes(term);
      return matchesSearch;
    });
  }, [search, stocksQuery.data]);

  const chartQueries = useQueries(
    filteredStocks.map((stock) => ({
      queryKey: ['market-summary', stock.ticker],
      queryFn: () => fetchPriceChart(stock.ticker),
      refetchInterval: 30_000
    }))
  );

  const rows = useMemo(() => {
    const enriched = filteredStocks.map((stock, index) => {
      const chartData = chartQueries[index]?.data || [];
      const summary = summarizeChart(chartData);
      return {
        ...stock,
        ...summary
      };
    });

    const withFilter =
      filter === 'gainers'
        ? enriched.filter((row) => Number(row.change_pct) >= 0)
        : filter === 'losers'
          ? enriched.filter((row) => Number(row.change_pct) < 0)
          : enriched;

    return withFilter.sort((a, b) => {
      if (sortKey === 'change_pct') {
        return Number(b.change_pct) - Number(a.change_pct);
      }
      if (sortKey === 'last_price') {
        return Number(b.last_price) - Number(a.last_price);
      }
      return Number(b.volume_24h) - Number(a.volume_24h);
    });
  }, [chartQueries, filter, filteredStocks, sortKey]);

  return (
    <section className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold text-white">Markets</h2>
        <p className="mt-1 text-sm text-slate-400">Search and track live exchange listings.</p>
      </div>

      <MarketsTable
        rows={rows}
        search={search}
        onSearchChange={setSearch}
        sortKey={sortKey}
        onSortChange={setSortKey}
        filter={filter}
        onFilterChange={setFilter}
        onRowClick={(row) => navigate(`/markets/${row.ticker}`)}
      />
    </section>
  );
}
