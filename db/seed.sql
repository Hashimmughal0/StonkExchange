-- Seed data for StockDB Exchange; hashed passwords correspond to the literal password

INSERT INTO users (username, email, password_hash, role)
VALUES
  ('alice', 'alice@example.com', '/ydw1Ic30E8wTRd37eK', 'user'),
  ('bob', 'bob@example.com', '/ydw1Ic30E8wTRd37eK', 'user'),
  ('admin', 'admin@example.com', '/ydw1Ic30E8wTRd37eK', 'admin'),
  ('liquidity_bot', 'liquidity_bot@example.com', '/ydw1Ic30E8wTRd37eK', 'user'),
  ('liquidity_seller', 'liquidity_seller@example.com', '/ydw1Ic30E8wTRd37eK', 'user')
ON CONFLICT (username) DO UPDATE
SET email = EXCLUDED.email,
    password_hash = EXCLUDED.password_hash,
    role = EXCLUDED.role;

INSERT INTO wallets (user_id, cash_balance)
SELECT user_id, 100000 FROM users WHERE username = 'alice'
ON CONFLICT (user_id) DO UPDATE
SET cash_balance = EXCLUDED.cash_balance;

INSERT INTO wallets (user_id, cash_balance)
SELECT user_id, 750000 FROM users WHERE username = 'bob'
ON CONFLICT (user_id) DO UPDATE
SET cash_balance = EXCLUDED.cash_balance;

INSERT INTO wallets (user_id, cash_balance)
SELECT user_id, 1000000 FROM users WHERE username = 'admin'
ON CONFLICT (user_id) DO UPDATE
SET cash_balance = EXCLUDED.cash_balance;

INSERT INTO wallets (user_id, cash_balance)
SELECT user_id, 5000000 FROM users WHERE username = 'liquidity_bot'
ON CONFLICT (user_id) DO UPDATE
SET cash_balance = EXCLUDED.cash_balance;

INSERT INTO wallets (user_id, cash_balance)
SELECT user_id, 2500000 FROM users WHERE username = 'liquidity_seller'
ON CONFLICT (user_id) DO UPDATE
SET cash_balance = EXCLUDED.cash_balance;

INSERT INTO stocks (ticker, company_name, last_price, total_shares)
VALUES
  ('AAPL', 'Apple Inc.', 170.15, 16000000000),
  ('TSLA', 'Tesla, Inc.', 220.45, 1200000000),
  ('MSFT', 'Microsoft Corp.', 330.10, 7700000000)
ON CONFLICT (ticker) DO UPDATE
SET company_name = EXCLUDED.company_name,
    last_price = EXCLUDED.last_price,
    total_shares = EXCLUDED.total_shares;

INSERT INTO price_history (stock_id, recorded_at, open_price, high_price, low_price, close_price, volume)
SELECT stock_id, NOW() - interval '1 hour', last_price * 0.98, last_price * 1.02, last_price * 0.97, last_price, 100000
FROM stocks
ON CONFLICT DO NOTHING;

INSERT INTO portfolios (user_id, stock_id, quantity, locked_quantity, average_price)
SELECT u.user_id, s.stock_id, 50, 0, s.last_price
FROM users u JOIN stocks s ON s.ticker = 'AAPL'
WHERE u.username = 'alice'
ON CONFLICT (user_id, stock_id) DO UPDATE
SET quantity = EXCLUDED.quantity,
    locked_quantity = EXCLUDED.locked_quantity,
    average_price = EXCLUDED.average_price;

INSERT INTO portfolios (user_id, stock_id, quantity, locked_quantity, average_price)
SELECT u.user_id, s.stock_id, 5000, 0, s.last_price
FROM users u
CROSS JOIN stocks s
WHERE u.username = 'liquidity_bot'
ON CONFLICT (user_id, stock_id) DO UPDATE
SET quantity = EXCLUDED.quantity,
    locked_quantity = EXCLUDED.locked_quantity,
    average_price = EXCLUDED.average_price;

INSERT INTO portfolios (user_id, stock_id, quantity, locked_quantity, average_price)
SELECT u.user_id, s.stock_id, 5000, 0, s.last_price
FROM users u
CROSS JOIN stocks s
WHERE u.username = 'liquidity_seller'
ON CONFLICT (user_id, stock_id) DO UPDATE
SET quantity = EXCLUDED.quantity,
    locked_quantity = EXCLUDED.locked_quantity,
    average_price = EXCLUDED.average_price;
