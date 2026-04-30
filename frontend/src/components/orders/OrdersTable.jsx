function money(value) {
  return Number(value || 0).toFixed(2);
}

export default function OrdersTable({ rows }) {
  return (
    <div className="glass-panel overflow-hidden">
      <table className="min-w-full text-left text-sm">
        <thead className="border-b border-border bg-white/5 text-slate-400">
          <tr>
            <th className="px-5 py-4">Type</th>
            <th className="px-5 py-4">Price</th>
            <th className="px-5 py-4">Quantity</th>
            <th className="px-5 py-4">Status</th>
            <th className="px-5 py-4">Date</th>
          </tr>
        </thead>
        <tbody>
          {rows.length === 0 ? (
            <tr>
              <td className="px-5 py-8 text-slate-400" colSpan={5}>
                No orders found for this filter.
              </td>
            </tr>
          ) : rows.map((row) => {
            const completed = ['filled', 'cancelled'].includes(String(row.status).toLowerCase());
            return (
              <tr key={row.order_id} className="border-b border-border/70">
                <td className={`px-5 py-4 font-semibold ${row.side === 'buy' ? 'text-green' : 'text-red'}`}>
                  {String(row.side || '').toUpperCase()}
                </td>
                <td className="px-5 py-4 text-slate-300">
                  ${money(row.effective_price || row.limit_price || row.price || row.last_price)}
                </td>
                <td className="px-5 py-4 text-slate-300">{Number(row.quantity || 0).toLocaleString()}</td>
                <td className="px-5 py-4">
                  <span
                    className={`rounded-full px-3 py-1 text-xs font-semibold uppercase tracking-wide ${
                      completed ? 'bg-green/10 text-green' : 'bg-accent/10 text-accent'
                    }`}
                  >
                    {row.status}
                  </span>
                </td>
                <td className="px-5 py-4 text-slate-400">
                  {new Date(row.created_at || row.updated_at).toLocaleString()}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
