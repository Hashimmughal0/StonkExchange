function formatNumber(value) {
  return Number(value || 0).toLocaleString(undefined, { maximumFractionDigits: 2 });
}

export default function MarketsTable({
  rows,
  search,
  onSearchChange,
  sortKey,
  onSortChange,
  filter,
  onFilterChange,
  onRowClick
}) {
  return (
    <div className="glass-panel overflow-hidden">
      <div className="flex flex-col gap-3 border-b border-border bg-white/5 p-4 lg:flex-row lg:items-center lg:justify-between">
        <div className="relative w-full lg:max-w-sm">
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-500"
          >
            <circle cx="11" cy="11" r="7" />
            <path d="M20 20l-3.5-3.5" />
          </svg>
          <input
            value={search}
            onChange={(e) => onSearchChange(e.target.value)}
            placeholder="Search symbol or name"
            className="w-full rounded-xl border border-border bg-panel2 py-3 pl-10 pr-4 text-sm outline-none transition focus:border-accent"
          />
        </div>

        <div className="flex flex-wrap gap-3">
          <select
            value={filter}
            onChange={(e) => onFilterChange(e.target.value)}
            className="rounded-xl border border-border bg-panel2 px-4 py-3 text-sm outline-none"
          >
            <option value="all">All markets</option>
            <option value="gainers">Gainers</option>
            <option value="losers">Losers</option>
          </select>

          <select
            value={sortKey}
            onChange={(e) => onSortChange(e.target.value)}
            className="rounded-xl border border-border bg-panel2 px-4 py-3 text-sm outline-none"
          >
            <option value="volume_24h">Sort by volume</option>
            <option value="last_price">Sort by price</option>
            <option value="change_pct">Sort by change</option>
          </select>
        </div>
      </div>

      <div className="overflow-x-auto">
        <table className="min-w-full text-left text-sm">
          <thead className="border-b border-border text-slate-400">
            <tr>
              <th className="px-5 py-4">Symbol</th>
              <th className="px-5 py-4">Name</th>
              <th className="px-5 py-4">Price</th>
              <th className="px-5 py-4">24h Change</th>
              <th className="px-5 py-4">Volume</th>
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 ? (
              <tr>
                <td className="px-5 py-8 text-slate-400" colSpan={5}>
                  No markets match your search.
                </td>
              </tr>
            ) : rows.map((row) => {
              const positive = Number(row.change_pct) >= 0;
              return (
                <tr
                  key={row.stock_id}
                  onClick={() => onRowClick(row)}
                  className="cursor-pointer border-b border-border/70 transition hover:bg-white/5"
                >
                  <td className="px-5 py-4 font-semibold text-white">{row.ticker}</td>
                  <td className="px-5 py-4 text-slate-300">{row.company_name}</td>
                  <td className="px-5 py-4 text-white">${formatNumber(row.last_price)}</td>
                  <td className={`px-5 py-4 font-medium ${positive ? 'text-green' : 'text-red'}`}>
                    <span className="inline-flex items-center gap-1">
                      <span>{positive ? '▲' : '▼'}</span>
                      {positive ? '+' : ''}
                      {formatNumber(row.change_pct)}%
                    </span>
                  </td>
                  <td className="px-5 py-4 text-slate-300">{formatNumber(row.volume_24h)}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
