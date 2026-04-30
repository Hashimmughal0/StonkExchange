import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis
} from 'recharts';

function formatPrice(value) {
  return Number(value || 0).toFixed(2);
}

export default function PriceChart({ data = [] }) {
  const formatted = data
    .filter((row) => row && row.recorded_at != null)
    .map((row) => ({
      ...row,
      close_price: Number(row.close_price || 0),
      recorded_at: new Date(row.recorded_at).toLocaleTimeString([], {
        hour: '2-digit',
        minute: '2-digit'
      })
    }));

  return (
    <div className="glass-panel h-[28rem] p-4">
      {formatted.length === 0 ? (
        <div className="flex h-full items-center justify-center rounded-2xl border border-border bg-white/5 text-sm text-slate-400">
          No chart data yet.
        </div>
      ) : (
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart data={formatted} margin={{ top: 10, right: 24, left: 8, bottom: 10 }}>
            <defs>
              <linearGradient id="priceFill" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#f0b90b" stopOpacity={0.35} />
                <stop offset="95%" stopColor="#f0b90b" stopOpacity={0.03} />
              </linearGradient>
            </defs>
            <CartesianGrid strokeDasharray="3 3" stroke="#1f2a3d" />
            <XAxis dataKey="recorded_at" stroke="#94a3b8" tick={{ fontSize: 12 }} />
            <YAxis
              stroke="#94a3b8"
              tickFormatter={formatPrice}
              domain={['auto', 'auto']}
              tick={{ fontSize: 12 }}
            />
            <Tooltip
              contentStyle={{ backgroundColor: '#0c1728', border: '1px solid #1f2a3d' }}
              labelStyle={{ color: '#e2e8f0' }}
            />
            <Area
              type="monotone"
              dataKey="close_price"
              stroke="#f0b90b"
              strokeWidth={2}
              fill="url(#priceFill)"
              dot={false}
              isAnimationActive={false}
              activeDot={{ r: 4 }}
            />
          </AreaChart>
        </ResponsiveContainer>
      )}
    </div>
  );
}
