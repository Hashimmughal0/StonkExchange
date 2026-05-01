-- Stored procedures for StockDB Exchange

CREATE OR REPLACE FUNCTION log_audit(
  entity TEXT,
  entity_id INT,
  actor_id INT,
  event_type TEXT,
  details JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID AS $$
BEGIN
  INSERT INTO audit_log (entity, entity_id, actor_id, event_type, details)
  VALUES (entity, entity_id, actor_id, event_type, details);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION gaussian_noise(p_stddev NUMERIC DEFAULT 1)
RETURNS NUMERIC AS $$
DECLARE
  u1 NUMERIC;
  u2 NUMERIC;
  z0 NUMERIC;
BEGIN
  u1 := GREATEST(random(), 0.0000001);
  u2 := random();
  z0 := SQRT(-2 * LN(u1)) * COS(2 * PI() * u2);
  RETURN z0 * COALESCE(p_stddev, 1);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION calc_recent_moving_average(p_stock_id INT, p_window INT DEFAULT 20)
RETURNS NUMERIC AS $$
DECLARE
  v_avg NUMERIC;
BEGIN
  SELECT AVG(close_price)
  INTO v_avg
  FROM (
    SELECT ph.close_price
    FROM price_history ph
    WHERE ph.stock_id = p_stock_id
    ORDER BY ph.recorded_at DESC
    LIMIT GREATEST(p_window, 1)
  ) x;

  RETURN COALESCE(v_avg, (SELECT last_price FROM stocks WHERE stock_id = p_stock_id), 1);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION calc_recent_volatility(p_stock_id INT, p_window INT DEFAULT 20)
RETURNS NUMERIC AS $$
DECLARE
  v_vol NUMERIC;
BEGIN
  SELECT COALESCE(STDDEV_SAMP(close_price), 0)
  INTO v_vol
  FROM (
    SELECT ph.close_price
    FROM price_history ph
    WHERE ph.stock_id = p_stock_id
    ORDER BY ph.recorded_at DESC
    LIMIT GREATEST(p_window, 2)
  ) x;

  RETURN COALESCE(v_vol, 0);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION calc_order_book_imbalance(p_stock_id INT)
RETURNS NUMERIC AS $$
DECLARE
  v_bid NUMERIC;
  v_ask NUMERIC;
BEGIN
  SELECT
    COALESCE(SUM(CASE WHEN side = 'buy' THEN quantity - filled_quantity ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN side = 'sell' THEN quantity - filled_quantity ELSE 0 END), 0)
  INTO v_bid, v_ask
  FROM orders
  WHERE stock_id = p_stock_id
    AND status IN ('open', 'partial');

  RETURN v_bid - v_ask;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION calc_fair_price(p_stock_id INT)
RETURNS NUMERIC AS $$
DECLARE
  v_last NUMERIC;
  v_ma NUMERIC;
  v_recent_trade NUMERIC;
  v_weighted NUMERIC;
BEGIN
  SELECT last_price INTO v_last
  FROM stocks
  WHERE stock_id = p_stock_id;

  SELECT AVG(price)
  INTO v_recent_trade
  FROM (
    SELECT t.price
    FROM trades t
    WHERE t.stock_id = p_stock_id
    ORDER BY t.executed_at DESC
    LIMIT 10
  ) x;

  v_ma := calc_recent_moving_average(p_stock_id, 20);

  v_weighted := (COALESCE(v_last, v_ma, 1) * 0.5)
    + (COALESCE(v_recent_trade, v_ma, COALESCE(v_last, 1)) * 0.3)
    + (COALESCE(v_ma, COALESCE(v_last, 1)) * 0.2);

  RETURN GREATEST(v_weighted, 0.01);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION bot_inventory_bias(p_user_id INT, p_stock_id INT)
RETURNS NUMERIC AS $$
DECLARE
  v_qty INT;
  v_avg NUMERIC;
  v_bias NUMERIC;
BEGIN
  SELECT quantity, average_price
  INTO v_qty, v_avg
  FROM portfolios
  WHERE user_id = p_user_id
    AND stock_id = p_stock_id;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  v_bias := LEAST(0.35, GREATEST(-0.35, (v_qty - 1000) / 10000.0));
  RETURN v_bias;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION ensure_bot_inventory(
  p_user_id INT,
  p_stock_id INT,
  p_target_quantity INT DEFAULT 250000,
  p_price NUMERIC DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
  INSERT INTO portfolios (user_id, stock_id, quantity, locked_quantity, average_price)
  VALUES (
    p_user_id,
    p_stock_id,
    GREATEST(p_target_quantity, 1),
    0,
    GREATEST(COALESCE(p_price, 1), 0.01)
  )
  ON CONFLICT (user_id, stock_id) DO UPDATE
  SET quantity = GREATEST(portfolios.quantity, EXCLUDED.quantity),
      locked_quantity = 0,
      average_price = COALESCE(portfolios.average_price, EXCLUDED.average_price);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION place_order(
  p_user INT,
  p_stock INT,
  p_order_type order_type,
  p_side order_side,
  p_quantity INT,
  p_limit_price NUMERIC,
  p_stop_price NUMERIC
)
RETURNS INT AS $$
DECLARE
  v_wallet wallets;
  v_stock stocks;
  v_portfolio portfolios;
  v_reserve NUMERIC;
  v_limit NUMERIC;
  v_store_limit NUMERIC;
  v_store_stop NUMERIC;
  v_book_price NUMERIC;
  v_order_id INT;
BEGIN
  IF p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than zero';
  END IF;

  SELECT * INTO v_stock FROM stocks WHERE stock_id = p_stock FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stock not found';
  END IF;

  SELECT * INTO v_wallet FROM wallets WHERE user_id = p_user FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Wallet missing for user %', p_user;
  END IF;

  v_limit := p_limit_price;
  IF p_order_type = 'market' THEN
    IF p_side = 'buy' THEN
      SELECT MIN(limit_price) INTO v_book_price
      FROM orders
      WHERE stock_id = p_stock
        AND side = 'sell'
        AND status IN ('open','partial')
        AND limit_price IS NOT NULL;
    ELSE
      SELECT MAX(limit_price) INTO v_book_price
      FROM orders
      WHERE stock_id = p_stock
        AND side = 'buy'
        AND status IN ('open','partial')
        AND limit_price IS NOT NULL;
    END IF;

    v_limit := COALESCE(
      v_book_price,
      v_stock.last_price,
      (SELECT close_price FROM price_history WHERE stock_id = p_stock ORDER BY recorded_at DESC LIMIT 1)
    );
  END IF;
  IF v_limit <= 0 THEN
    RAISE EXCEPTION 'Market price unavailable for stock %', p_stock;
  END IF;

  v_store_limit := CASE
    WHEN p_order_type = 'market' THEN NULL
    ELSE p_limit_price
  END;
  v_store_stop := CASE
    WHEN p_order_type = 'stop_loss' THEN p_stop_price
    ELSE NULL
  END;

  IF p_order_type = 'limit' AND v_store_limit IS NULL THEN
    RAISE EXCEPTION 'Limit orders require a limit price';
  END IF;
  IF p_order_type = 'stop_loss' AND (v_store_limit IS NULL OR v_store_stop IS NULL) THEN
    RAISE EXCEPTION 'Stop loss orders require both limit and stop prices';
  END IF;

  IF p_side = 'buy' THEN
    v_reserve := v_limit * p_quantity;
    IF v_wallet.cash_balance < v_reserve THEN
      RAISE EXCEPTION 'Insufficient cash: need % but have %', v_reserve, v_wallet.cash_balance;
    END IF;
    UPDATE wallets
    SET cash_balance = cash_balance - v_reserve,
        reserved_balance = reserved_balance + v_reserve,
        updated_at = NOW()
    WHERE wallet_id = v_wallet.wallet_id;
  ELSE
    SELECT * INTO v_portfolio FROM portfolios WHERE user_id = p_user AND stock_id = p_stock FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'No holdings to sell';
    END IF;
    IF v_portfolio.quantity - v_portfolio.locked_quantity < p_quantity THEN
      RAISE EXCEPTION 'Not enough shares to lock';
    END IF;
    UPDATE portfolios
    SET locked_quantity = locked_quantity + p_quantity
    WHERE portfolio_id = v_portfolio.portfolio_id;
  END IF;

  INSERT INTO orders (user_id, stock_id, order_type, side, quantity, limit_price, stop_price)
  VALUES (p_user, p_stock, p_order_type, p_side, p_quantity, v_store_limit, v_store_stop)
  RETURNING order_id INTO v_order_id;

  PERFORM log_audit(
    'orders',
    v_order_id,
    p_user,
    'placed',
    jsonb_build_object('side', p_side, 'quantity', p_quantity, 'type', p_order_type)
  );

  RETURN v_order_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION execute_trade(
  p_buy_order INT,
  p_sell_order INT,
  p_quantity INT,
  p_price NUMERIC
)
RETURNS INT AS $$
DECLARE
  v_trade_id INT;
BEGIN
  INSERT INTO trades (buy_order_id, sell_order_id, stock_id, quantity, price)
  SELECT p_buy_order, p_sell_order, o.stock_id, p_quantity, p_price
  FROM orders o
  WHERE o.order_id = p_buy_order
  RETURNING trade_id INTO v_trade_id;

  UPDATE orders
  SET filled_quantity = filled_quantity + p_quantity,
      status = CASE
        WHEN filled_quantity + p_quantity >= quantity THEN 'filled'::order_status
        ELSE 'partial'::order_status
      END,
      updated_at = NOW()
  WHERE order_id IN (p_buy_order, p_sell_order);

  PERFORM log_audit(
    'trades',
    v_trade_id,
    NULL,
    'executed',
    jsonb_build_object(
      'buy_order', p_buy_order,
      'sell_order', p_sell_order,
      'quantity', p_quantity,
      'price', p_price
    )
  );
  PERFORM settle_trade(v_trade_id);

  RETURN v_trade_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION settle_trade(p_trade_id INT)
RETURNS VOID AS $$
DECLARE
  t trades;
  v_buy_order orders;
  v_sell_order orders;
  v_buy_wallet wallets;
  v_sell_wallet wallets;
  v_amount NUMERIC;
BEGIN
  SELECT * INTO t FROM trades WHERE trade_id = p_trade_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Trade % not found', p_trade_id;
  END IF;

  v_amount := t.quantity * t.price;

  SELECT * INTO v_buy_order FROM orders WHERE order_id = t.buy_order_id;
  SELECT * INTO v_sell_order FROM orders WHERE order_id = t.sell_order_id;

  SELECT * INTO v_buy_wallet FROM wallets WHERE user_id = v_buy_order.user_id FOR UPDATE;
  UPDATE wallets
  SET reserved_balance = GREATEST(reserved_balance - v_amount, 0),
      updated_at = NOW()
  WHERE wallet_id = v_buy_wallet.wallet_id;

  SELECT * INTO v_sell_wallet FROM wallets WHERE user_id = v_sell_order.user_id FOR UPDATE;
  UPDATE wallets
  SET cash_balance = cash_balance + v_amount,
      updated_at = NOW()
  WHERE wallet_id = v_sell_wallet.wallet_id;

  INSERT INTO portfolios (user_id, stock_id, quantity, average_price)
  VALUES (v_buy_order.user_id, t.stock_id, t.quantity, t.price)
  ON CONFLICT (user_id, stock_id) DO UPDATE
  SET quantity = portfolios.quantity + EXCLUDED.quantity,
      average_price = (
        (portfolios.average_price * portfolios.quantity) +
        (EXCLUDED.average_price * EXCLUDED.quantity)
      ) / NULLIF(portfolios.quantity + EXCLUDED.quantity, 0);

  UPDATE portfolios
  SET locked_quantity = GREATEST(locked_quantity - t.quantity, 0),
      quantity = GREATEST(quantity - t.quantity, 0)
  WHERE user_id = v_sell_order.user_id
    AND stock_id = t.stock_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION match_orders(p_stock INT)
RETURNS VOID AS $$
DECLARE
  v_buy orders;
  v_sell orders;
  v_price NUMERIC;
  v_qty INT;
BEGIN
  LOOP
    SELECT * INTO v_buy
    FROM orders
    WHERE stock_id = p_stock
      AND side = 'buy'
      AND status IN ('open','partial')
    ORDER BY limit_price DESC NULLS LAST, created_at
    LIMIT 1
    FOR UPDATE SKIP LOCKED;

    SELECT * INTO v_sell
    FROM orders
    WHERE stock_id = p_stock
      AND side = 'sell'
      AND status IN ('open','partial')
    ORDER BY limit_price ASC NULLS LAST, created_at
    LIMIT 1
    FOR UPDATE SKIP LOCKED;

    EXIT WHEN v_buy IS NULL OR v_sell IS NULL;
    EXIT WHEN v_buy.limit_price < v_sell.limit_price;

    v_qty := LEAST(v_buy.quantity - v_buy.filled_quantity, v_sell.quantity - v_sell.filled_quantity);
    EXIT WHEN v_qty < 1;

    v_price := COALESCE(
      v_sell.limit_price,
      v_buy.limit_price,
      (SELECT last_price FROM stocks WHERE stock_id = p_stock)
    );
    PERFORM execute_trade(v_buy.order_id, v_sell.order_id, v_qty, v_price);
  END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION cancel_order(p_order INT, p_user INT)
RETURNS VOID AS $$
DECLARE
  o orders;
  v_wallet wallets;
  v_portfolio portfolios;
  v_remaining INT;
  v_amount NUMERIC;
BEGIN
  SELECT * INTO o FROM orders WHERE order_id = p_order AND user_id = p_user FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF o.status = 'filled' THEN
    RETURN;
  END IF;

  v_remaining := o.quantity - o.filled_quantity;
  v_amount := v_remaining * COALESCE(o.limit_price, 0);

  IF o.side = 'buy' THEN
    SELECT * INTO v_wallet FROM wallets WHERE user_id = p_user FOR UPDATE;
    UPDATE wallets
    SET cash_balance = cash_balance + v_amount,
        reserved_balance = GREATEST(reserved_balance - v_amount, 0),
        updated_at = NOW()
    WHERE wallet_id = v_wallet.wallet_id;
  ELSE
    SELECT * INTO v_portfolio FROM portfolios WHERE user_id = p_user AND stock_id = o.stock_id FOR UPDATE;
    UPDATE portfolios
    SET locked_quantity = GREATEST(locked_quantity - v_remaining, 0)
    WHERE portfolio_id = v_portfolio.portfolio_id;
  END IF;

  UPDATE orders
  SET status = 'cancelled'::order_status,
      updated_at = NOW()
  WHERE order_id = p_order;

  PERFORM log_audit(
    'orders',
    p_order,
    p_user,
    'cancelled',
    jsonb_build_object('remaining', v_remaining)
  );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION deposit_funds(p_user INT, p_amount NUMERIC)
RETURNS VOID AS $$
DECLARE
  v_wallet wallets;
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Deposit amount must be positive';
  END IF;

  SELECT * INTO v_wallet FROM wallets WHERE user_id = p_user FOR UPDATE;
  UPDATE wallets
  SET cash_balance = cash_balance + p_amount,
      updated_at = NOW()
  WHERE wallet_id = v_wallet.wallet_id;

  PERFORM log_audit(
    'wallets',
    v_wallet.wallet_id,
    p_user,
    'deposit',
    jsonb_build_object('amount', p_amount)
  );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION withdraw_funds(p_user INT, p_amount NUMERIC)
RETURNS VOID AS $$
DECLARE
  v_wallet wallets;
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Withdrawal amount must be positive';
  END IF;

  SELECT * INTO v_wallet FROM wallets WHERE user_id = p_user FOR UPDATE;
  IF v_wallet.cash_balance < p_amount THEN
    RAISE EXCEPTION 'Insufficient cash for withdrawal';
  END IF;

  UPDATE wallets
  SET cash_balance = cash_balance - p_amount,
      updated_at = NOW()
  WHERE wallet_id = v_wallet.wallet_id;

  PERFORM log_audit(
    'wallets',
    v_wallet.wallet_id,
    p_user,
    'withdraw',
    jsonb_build_object('amount', p_amount)
  );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION simulate_market_tick(p_moves INT DEFAULT 5)
RETURNS INT AS $$
DECLARE
  v_stock RECORD;
  v_fair NUMERIC;
  v_factor NUMERIC;
  v_old_price NUMERIC;
  v_new_price NUMERIC;
  v_move_cap NUMERIC;
  v_vol NUMERIC;
  v_imbalance NUMERIC;
  v_moves INT := 0;
BEGIN
  FOR v_stock IN
    SELECT stock_id, ticker, last_price
    FROM stocks
    WHERE is_active = TRUE
    ORDER BY random()
    LIMIT GREATEST(p_moves, 1)
    FOR UPDATE SKIP LOCKED
  LOOP
    v_old_price := GREATEST(COALESCE(v_stock.last_price, 1), 0.01);
    v_fair := calc_fair_price(v_stock.stock_id);
    v_vol := calc_recent_volatility(v_stock.stock_id, 20);
    v_imbalance := calc_order_book_imbalance(v_stock.stock_id);
    v_move_cap := GREATEST(v_old_price * 0.05, 0.01);

    v_factor := LEAST(
      v_move_cap,
      GREATEST(
        -v_move_cap,
        ((v_fair - v_old_price) * 0.15)
        + (COALESCE(v_imbalance, 0) / GREATEST(v_old_price * 20000, 1))
        + gaussian_noise(GREATEST(v_old_price * (0.002 + LEAST(v_vol / GREATEST(v_old_price, 1), 0.02)), 0.01))
      )
    );

    v_new_price := GREATEST(0.01, ROUND((v_old_price + v_factor)::numeric, 4));

    UPDATE stocks
    SET last_price = v_new_price
    WHERE stock_id = v_stock.stock_id;

    INSERT INTO price_history (
      stock_id,
      recorded_at,
      open_price,
      high_price,
      low_price,
      close_price,
      volume
    )
    VALUES (
      v_stock.stock_id,
      NOW(),
      v_old_price,
      GREATEST(v_old_price, v_new_price),
      LEAST(v_old_price, v_new_price),
      v_new_price,
      0
    );

    PERFORM log_audit(
      'stocks',
      v_stock.stock_id,
      NULL,
      'price_tick',
      jsonb_build_object(
        'ticker', v_stock.ticker,
        'old_price', v_old_price,
        'new_price', v_new_price
      )
    );

    v_moves := v_moves + 1;
  END LOOP;

  RETURN v_moves;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION place_bot_ladder_orders(
  p_user_id INT,
  p_stock_id INT,
  p_levels INT,
  p_base_price NUMERIC,
  p_spread NUMERIC,
  p_side_bias NUMERIC,
  p_aggressiveness NUMERIC
)
RETURNS INT AS $$
DECLARE
  v_stock RECORD;
  v_existing RECORD;
  v_level INT;
  v_quantity INT;
  v_bid_price NUMERIC;
  v_ask_price NUMERIC;
  v_target_side order_side;
  v_order_type order_type := 'limit';
  v_created INT := 0;
BEGIN
  SELECT * INTO v_stock FROM stocks WHERE stock_id = p_stock_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  FOR v_level IN 1..GREATEST(p_levels, 1) LOOP
    v_quantity := GREATEST(
      ROUND(100 + (ABS(p_side_bias) * 80) + (random() * 120))::INT,
      10
    );

    v_bid_price := GREATEST(ROUND((p_base_price - (p_spread * v_level))::numeric, 4), 0.01);
    v_ask_price := GREATEST(ROUND((p_base_price + (p_spread * v_level))::numeric, 4), 0.01);

    IF p_side_bias >= 0 THEN
      v_quantity := GREATEST(ROUND(v_quantity * (1 + p_side_bias))::INT, 10);
    ELSE
      v_quantity := GREATEST(ROUND(v_quantity * (1 - p_side_bias))::INT, 10);
    END IF;

    SELECT order_id, side, limit_price, quantity, filled_quantity
    INTO v_existing
    FROM orders
    WHERE user_id = p_user_id
      AND stock_id = p_stock_id
      AND status IN ('open', 'partial')
      AND order_type = 'limit'
      AND side = 'buy'
      AND limit_price = v_bid_price
    LIMIT 1;

    IF FOUND THEN
      UPDATE orders
      SET quantity = GREATEST(quantity, v_quantity),
          updated_at = NOW()
      WHERE order_id = v_existing.order_id;
    ELSE
      PERFORM place_order(
        p_user_id,
        p_stock_id,
        v_order_type,
        'buy'::order_side,
        v_quantity,
        v_bid_price,
        NULL
      );
      v_created := v_created + 1;
    END IF;

    SELECT order_id, side, limit_price, quantity, filled_quantity
    INTO v_existing
    FROM orders
    WHERE user_id = p_user_id
      AND stock_id = p_stock_id
      AND status IN ('open', 'partial')
      AND order_type = 'limit'
      AND side = 'sell'
      AND limit_price = v_ask_price
    LIMIT 1;

    IF FOUND THEN
      UPDATE orders
      SET quantity = GREATEST(quantity, v_quantity),
          updated_at = NOW()
      WHERE order_id = v_existing.order_id;
    ELSE
      PERFORM place_order(
        p_user_id,
        p_stock_id,
        v_order_type,
        'sell'::order_side,
        v_quantity,
        v_ask_price,
        NULL
      );
      v_created := v_created + 1;
    END IF;
  END LOOP;

  RETURN v_created;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION simulate_intelligent_tick(p_stock_id INT, p_moves INT DEFAULT 3)
RETURNS INT AS $$
DECLARE
  v_stock RECORD;
  v_fair NUMERIC;
  v_vol NUMERIC;
  v_spread NUMERIC;
  v_imbalance NUMERIC;
  v_price NUMERIC;
  v_market_maker_id INT;
  v_noise_trader_id INT;
  v_momentum_trader_id INT;
  v_arbitrage_bot_id INT;
  v_depth_levels INT;
  v_created INT := 0;
  v_buy_bias NUMERIC;
  v_sell_bias NUMERIC;
  v_signal NUMERIC;
BEGIN
  SELECT * INTO v_stock
  FROM stocks
  WHERE stock_id = p_stock_id
    AND is_active = TRUE
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  SELECT user_id INTO v_market_maker_id FROM users WHERE username = 'liquidity_bot';
  SELECT user_id INTO v_noise_trader_id FROM users WHERE username = 'noise_trader';
  SELECT user_id INTO v_momentum_trader_id FROM users WHERE username = 'momentum_trader';
  SELECT user_id INTO v_arbitrage_bot_id FROM users WHERE username = 'arbitrage_bot';

  v_price := GREATEST(COALESCE(v_stock.last_price, 1), 0.01);
  v_fair := calc_fair_price(p_stock_id);
  v_vol := GREATEST(calc_recent_volatility(p_stock_id, 20), v_price * 0.002);
  v_imbalance := calc_order_book_imbalance(p_stock_id);
  v_spread := GREATEST(v_price * LEAST(0.01 + (v_vol / GREATEST(v_price, 1)) * 2, 0.05), 0.01);
  v_depth_levels := LEAST(GREATEST(p_moves, 3), 5);

  IF v_price < 0.05 OR v_price < v_fair * 0.25 THEN
    v_buy_bias := 0.35;
  ELSE
    v_buy_bias := 0;
  END IF;

  v_sell_bias := bot_inventory_bias(v_market_maker_id, p_stock_id);
  IF v_imbalance < 0 THEN
    v_buy_bias := v_buy_bias + 0.15;
  ELSIF v_imbalance > 0 THEN
    v_sell_bias := v_sell_bias + 0.15;
  END IF;

  IF v_market_maker_id IS NOT NULL THEN
    PERFORM ensure_bot_inventory(v_market_maker_id, p_stock_id, 250000, v_fair);
    v_created := v_created + place_bot_ladder_orders(
      v_market_maker_id,
      p_stock_id,
      v_depth_levels,
      GREATEST((v_price * 0.45) + (v_fair * 0.55), 0.01),
      v_spread,
      v_sell_bias,
      0.5
    );
  END IF;

  IF v_noise_trader_id IS NOT NULL THEN
    PERFORM ensure_bot_inventory(v_noise_trader_id, p_stock_id, 50000, v_price);
    v_created := v_created + place_bot_ladder_orders(
      v_noise_trader_id,
      p_stock_id,
      1,
      v_price + gaussian_noise(v_spread * 0.15),
      GREATEST(v_spread * 0.5, 0.01),
      0,
      0.2
    );
  END IF;

  IF v_momentum_trader_id IS NOT NULL THEN
    PERFORM ensure_bot_inventory(v_momentum_trader_id, p_stock_id, 50000, v_price);
    v_signal := GREATEST(LEAST((v_price - v_fair) / GREATEST(v_fair, 1), 0.03), -0.03);
    v_created := v_created + place_bot_ladder_orders(
      v_momentum_trader_id,
      p_stock_id,
      1,
      v_price + (v_signal * v_price),
      GREATEST(v_spread * 0.8, 0.01),
      CASE WHEN v_signal >= 0 THEN 0.15 ELSE -0.15 END,
      0.35
    );
  END IF;

  IF v_arbitrage_bot_id IS NOT NULL AND ABS(v_price - v_fair) / GREATEST(v_fair, 1) > 0.01 THEN
    PERFORM ensure_bot_inventory(v_arbitrage_bot_id, p_stock_id, 75000, v_fair);
    v_created := v_created + place_bot_ladder_orders(
      v_arbitrage_bot_id,
      p_stock_id,
      1,
      v_fair,
      GREATEST(v_spread * 0.6, 0.01),
      CASE WHEN v_price < v_fair THEN 0.2 ELSE -0.2 END,
      0.45
    );
  END IF;

  IF v_price < v_fair * 0.8 THEN
    IF v_market_maker_id IS NOT NULL THEN
      PERFORM ensure_bot_inventory(v_market_maker_id, p_stock_id, 300000, v_fair);
    END IF;
    v_created := v_created + place_bot_ladder_orders(
      v_market_maker_id,
      p_stock_id,
      2,
      v_fair,
      GREATEST(v_spread * 1.2, 0.01),
      0.4,
      0.6
    );
  END IF;

  PERFORM match_orders(p_stock_id);
  RETURN v_created;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION simulate_liquidity_engine(p_ticks INT DEFAULT 5)
RETURNS INT AS $$
DECLARE
  v_stock RECORD;
  v_total INT := 0;
BEGIN
  FOR v_stock IN
    SELECT stock_id
    FROM stocks
    WHERE is_active = TRUE
    ORDER BY stock_id
    LIMIT GREATEST(p_ticks, 1)
  LOOP
    v_total := v_total + simulate_intelligent_tick(v_stock.stock_id, 5);
    v_total := v_total + simulate_market_tick(1);
  END LOOP;

  RETURN v_total;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION simulate_market_activity(p_orders INT DEFAULT 3)
RETURNS INT AS $$
BEGIN
  RETURN simulate_liquidity_engine(p_orders);
END;
$$ LANGUAGE plpgsql;
