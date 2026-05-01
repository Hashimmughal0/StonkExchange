-- Views for Market data and dashboards

DROP VIEW IF EXISTS v_stock_summary;
DROP VIEW IF EXISTS v_trade_history;
DROP VIEW IF EXISTS v_all_orders;
DROP VIEW IF EXISTS v_open_orders;
DROP VIEW IF EXISTS v_user_portfolio;
DROP VIEW IF EXISTS v_order_book;

CREATE VIEW v_order_book AS
SELECT o.stock_id,
       s.ticker,
       o.side,
       o.limit_price,
       SUM(o.quantity - o.filled_quantity) AS total_quantity,
       COUNT(*) AS order_count
FROM orders o
JOIN stocks s ON s.stock_id = o.stock_id
WHERE o.status IN ('open','partial')
  AND o.limit_price IS NOT NULL
GROUP BY o.stock_id, s.ticker, o.side, o.limit_price;

CREATE VIEW v_user_portfolio AS
SELECT p.user_id,
       p.stock_id,
       s.ticker,
       p.quantity,
       p.locked_quantity,
       p.average_price,
       s.last_price,
       (p.quantity * s.last_price) - (p.quantity * p.average_price) AS unrealized_pl
FROM portfolios p
JOIN stocks s ON s.stock_id = p.stock_id;

CREATE VIEW v_all_orders AS
SELECT o.order_id,
       o.user_id,
       o.stock_id,
       s.ticker,
       o.side,
       o.order_type,
       o.status,
       o.quantity,
       o.filled_quantity,
       o.limit_price,
       CASE
         WHEN o.order_type = 'market' THEN s.last_price
         ELSE o.limit_price
       END AS effective_price,
       (o.quantity - o.filled_quantity) AS remaining_quantity,
       o.created_at,
       o.updated_at
FROM orders o
JOIN stocks s ON s.stock_id = o.stock_id;

CREATE VIEW v_open_orders AS
SELECT o.order_id,
       o.user_id,
       o.stock_id,
       s.ticker,
       o.side,
       o.order_type,
       o.status,
       o.quantity,
       o.filled_quantity,
       o.limit_price,
       CASE
         WHEN o.order_type = 'market' THEN s.last_price
         ELSE o.limit_price
       END AS effective_price,
       (o.quantity - o.filled_quantity) AS remaining_quantity,
       o.created_at,
       o.updated_at
FROM orders o
JOIN stocks s ON s.stock_id = o.stock_id
WHERE o.status IN ('open','partial');

CREATE VIEW v_trade_history AS
SELECT t.trade_id,
       t.stock_id,
       s.ticker,
       t.price,
       t.quantity,
       t.executed_at
FROM trades t
JOIN stocks s ON s.stock_id = t.stock_id
ORDER BY t.executed_at DESC;

CREATE VIEW v_stock_summary AS
SELECT s.stock_id,
       s.ticker,
       s.company_name,
       s.last_price,
       COALESCE(((s.last_price - prev.price) / NULLIF(prev.price, 0)) * 100, 0) AS change_pct,
       COALESCE(x.volume_24h, 0) AS volume_24h,
       COALESCE(book.best_bid, 0) AS best_bid,
       COALESCE(book.best_ask, 0) AS best_ask
FROM stocks s
LEFT JOIN LATERAL (
  SELECT close_price AS price
  FROM price_history ph
  WHERE ph.stock_id = s.stock_id
    AND ph.recorded_at >= NOW() - INTERVAL '24 hours'
  ORDER BY ph.recorded_at ASC
  LIMIT 1
) prev ON TRUE
LEFT JOIN LATERAL (
  SELECT SUM(t.quantity) AS volume_24h
  FROM trades t
  WHERE t.stock_id = s.stock_id
    AND t.executed_at >= NOW() - INTERVAL '24 hours'
) x ON TRUE
LEFT JOIN LATERAL (
  SELECT MAX(CASE WHEN side = 'buy' THEN limit_price END) AS best_bid,
         MIN(CASE WHEN side = 'sell' THEN limit_price END) AS best_ask
  FROM orders o
  WHERE o.stock_id = s.stock_id
    AND o.status IN ('open','partial')
) book ON TRUE;
