-- Schema for StockDB Exchange

DROP TABLE IF EXISTS sessions;
DROP TABLE IF EXISTS audit_log;
DROP TABLE IF EXISTS trades;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS portfolios;
DROP TABLE IF EXISTS price_history;
DROP TABLE IF EXISTS stocks;
DROP TABLE IF EXISTS wallets;
DROP TABLE IF EXISTS users;

DROP TYPE IF EXISTS order_status;
DROP TYPE IF EXISTS order_side;
DROP TYPE IF EXISTS order_type;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE order_type AS ENUM ('market','limit','stop_loss');
CREATE TYPE order_side AS ENUM ('buy','sell');
CREATE TYPE order_status AS ENUM ('open','partial','filled','cancelled');

CREATE TABLE users (
  user_id SERIAL PRIMARY KEY,
  username VARCHAR(50) NOT NULL UNIQUE,
  email VARCHAR(150) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  role VARCHAR(10) NOT NULL DEFAULT 'user' CHECK (role IN ('user','admin')),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE wallets (
  wallet_id SERIAL PRIMARY KEY,
  user_id INT NOT NULL UNIQUE REFERENCES users(user_id) ON DELETE CASCADE,
  cash_balance NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (cash_balance >= 0),
  reserved_balance NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (reserved_balance >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE stocks (
  stock_id SERIAL PRIMARY KEY,
  ticker VARCHAR(10) NOT NULL UNIQUE,
  company_name VARCHAR(200) NOT NULL,
  last_price NUMERIC(12,4) NOT NULL DEFAULT 0 CHECK (last_price >= 0),
  total_shares BIGINT NOT NULL DEFAULT 0 CHECK (total_shares >= 0),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sessions (
  token TEXT PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE audit_log (
  audit_id SERIAL PRIMARY KEY,
  entity VARCHAR(60) NOT NULL,
  entity_id INT,
  actor_id INT,
  event_type VARCHAR(60) NOT NULL,
  details JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE orders (
  order_id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(user_id),
  stock_id INT NOT NULL REFERENCES stocks(stock_id),
  order_type order_type NOT NULL,
  side order_side NOT NULL,
  quantity INT NOT NULL CHECK (quantity > 0),
  filled_quantity INT NOT NULL DEFAULT 0 CHECK (filled_quantity >= 0),
  limit_price NUMERIC(12,4),
  stop_price NUMERIC(12,4),
  status order_status NOT NULL DEFAULT 'open',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (
    (order_type = 'market' AND limit_price IS NULL AND stop_price IS NULL) OR
    (order_type = 'limit' AND limit_price IS NOT NULL AND stop_price IS NULL) OR
    (order_type = 'stop_loss' AND limit_price IS NOT NULL AND stop_price IS NOT NULL)
  )
);

CREATE TABLE trades (
  trade_id SERIAL PRIMARY KEY,
  buy_order_id INT NOT NULL REFERENCES orders(order_id),
  sell_order_id INT NOT NULL REFERENCES orders(order_id),
  stock_id INT NOT NULL REFERENCES stocks(stock_id),
  quantity INT NOT NULL CHECK (quantity > 0),
  price NUMERIC(12,4) NOT NULL CHECK (price >= 0),
  executed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE portfolios (
  portfolio_id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  stock_id INT NOT NULL REFERENCES stocks(stock_id),
  quantity INT NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  locked_quantity INT NOT NULL DEFAULT 0 CHECK (locked_quantity >= 0),
  average_price NUMERIC(12,4) NOT NULL DEFAULT 0,
  UNIQUE (user_id, stock_id)
);

CREATE TABLE price_history (
  price_id SERIAL PRIMARY KEY,
  stock_id INT NOT NULL REFERENCES stocks(stock_id),
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  open_price NUMERIC(12,4) NOT NULL,
  high_price NUMERIC(12,4) NOT NULL,
  low_price NUMERIC(12,4) NOT NULL,
  close_price NUMERIC(12,4) NOT NULL,
  volume BIGINT NOT NULL DEFAULT 0
);

CREATE INDEX idx_orders_stock_status_side ON orders (stock_id, status, side, limit_price);
CREATE INDEX idx_orders_user_status ON orders (user_id, status);
CREATE INDEX idx_trades_stock_exec ON trades (stock_id, executed_at DESC);
CREATE INDEX idx_price_history_stock_time ON price_history (stock_id, recorded_at DESC);
CREATE INDEX idx_portfolios_user ON portfolios (user_id);
CREATE INDEX idx_wallets_user ON wallets (user_id);
CREATE INDEX idx_audit_log_entity ON audit_log (entity, event_type, created_at DESC);
