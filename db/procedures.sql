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

  DECLARE
    v_wallet_row wallets;
  BEGIN
    FOR v_wallet_row IN
      SELECT * FROM wallets
      WHERE user_id IN (v_buy_order.user_id, v_sell_order.user_id)
      ORDER BY wallet_id
      FOR UPDATE
    LOOP
      IF v_wallet_row.user_id = v_buy_order.user_id THEN
        v_buy_wallet := v_wallet_row;
      END IF;
      IF v_wallet_row.user_id = v_sell_order.user_id THEN
        v_sell_wallet := v_wallet_row;
      END IF;
    END LOOP;
  END;

  IF v_buy_wallet.wallet_id IS NULL THEN
    RAISE EXCEPTION 'Buyer wallet not found for user %', v_buy_order.user_id;
  END IF;
  IF v_sell_wallet.wallet_id IS NULL THEN
    RAISE EXCEPTION 'Seller wallet not found for user %', v_sell_order.user_id;
  END IF;

  UPDATE wallets
  SET reserved_balance = GREATEST(reserved_balance - v_amount, 0),
      updated_at = NOW()
  WHERE wallet_id = v_buy_wallet.wallet_id;

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
    ORDER BY (limit_price IS NULL) DESC, limit_price DESC NULLS LAST, created_at
    LIMIT 1
    FOR UPDATE SKIP LOCKED;

    SELECT * INTO v_sell
    FROM orders
    WHERE stock_id = p_stock
      AND side = 'sell'
      AND status IN ('open','partial')
    ORDER BY (limit_price IS NULL) DESC, limit_price ASC NULLS LAST, created_at
    LIMIT 1
    FOR UPDATE SKIP LOCKED;

    EXIT WHEN v_buy IS NULL OR v_sell IS NULL;
    EXIT WHEN (v_buy.limit_price IS NOT NULL AND v_sell.limit_price IS NOT NULL AND v_buy.limit_price < v_sell.limit_price);

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

  v_old_price NUMERIC;
  v_new_price NUMERIC;

  v_bid_qty NUMERIC;
  v_ask_qty NUMERIC;
  v_imbalance NUMERIC;

  v_trend NUMERIC;
  v_noise NUMERIC;
  v_mean_reversion NUMERIC;

  v_fair_price NUMERIC;
  v_volatility NUMERIC;

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
    v_old_price := COALESCE(v_stock.last_price, 10);

    -- ✅ Fetch order book separately (NO locking issue)
    SELECT
      COALESCE(SUM(CASE WHEN side = 'buy' THEN quantity - filled_quantity END), 0),
      COALESCE(SUM(CASE WHEN side = 'sell' THEN quantity - filled_quantity END), 0)
    INTO v_bid_qty, v_ask_qty
    FROM orders
    WHERE stock_id = v_stock.stock_id
      AND status IN ('open','partial');

    -- imbalance
    IF (v_bid_qty + v_ask_qty) > 0 THEN
      v_imbalance := (v_bid_qty - v_ask_qty) / (v_bid_qty + v_ask_qty);
    ELSE
      v_imbalance := 0;
    END IF;

    -- fair price
    SELECT COALESCE(AVG(close_price), v_old_price)
    INTO v_fair_price
    FROM (
      SELECT close_price
      FROM price_history
      WHERE stock_id = v_stock.stock_id
      ORDER BY recorded_at DESC
      LIMIT 20
    ) t;

    v_mean_reversion := (v_fair_price - v_old_price) / v_old_price;

    -- volatility
    v_volatility := GREATEST(0.002, LEAST(0.02, ABS(v_imbalance) * 0.02 + 0.005));

    -- components
    v_trend := v_imbalance * 0.01;
    v_noise := (random() - 0.5) * v_volatility;

    -- final price
    v_new_price := v_old_price * (
      1
      + (v_trend * 0.6)
      + (v_noise * 0.4)
      + (v_mean_reversion * 0.1)
    );

    v_new_price := GREATEST(1, ROUND(v_new_price, 4));

    -- update stock
    UPDATE stocks
    SET last_price = v_new_price
    WHERE stock_id = v_stock.stock_id;

    -- history
    INSERT INTO price_history (
      stock_id, recorded_at,
      open_price, high_price, low_price, close_price, volume
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

    v_moves := v_moves + 1;
  END LOOP;

  RETURN v_moves;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION simulate_market_activity(p_orders INT DEFAULT 3)
RETURNS INT AS $$
DECLARE
  v_buyer_bot_id INT;
  v_seller_bot_id INT;

  v_stock RECORD;

  v_price NUMERIC;
  v_spread NUMERIC;

  v_bid_qty NUMERIC;
  v_ask_qty NUMERIC;
  v_imbalance NUMERIC;

  v_activity NUMERIC;
  v_levels INT;

  v_quantity INT;
  v_buy_limit NUMERIC;
  v_sell_limit NUMERIC;

  v_created INT := 0;
  i INT;
BEGIN
  -- Get bot users
  SELECT user_id INTO v_buyer_bot_id FROM users WHERE username = 'liquidity_bot';
  SELECT user_id INTO v_seller_bot_id FROM users WHERE username = 'liquidity_seller';

  IF v_buyer_bot_id IS NULL OR v_seller_bot_id IS NULL THEN
    RAISE EXCEPTION 'Liquidity bot users are missing';
  END IF;

  -- Keep bots funded
  UPDATE wallets
  SET cash_balance = GREATEST(cash_balance, 5000000),
      reserved_balance = 0,
      updated_at = NOW()
  WHERE user_id IN (v_buyer_bot_id, v_seller_bot_id);

  -- Cancel only stale bot orders (NOT all orders)
  FOR v_stock IN
    SELECT order_id, user_id
    FROM orders
    WHERE user_id IN (v_buyer_bot_id, v_seller_bot_id)
      AND status IN ('open','partial')
      AND created_at < NOW() - INTERVAL '5 seconds'
  LOOP
    PERFORM cancel_order(v_stock.order_id, v_stock.user_id);
  END LOOP;

  -- Loop through random active stocks
  FOR v_stock IN
    SELECT stock_id, last_price
    FROM stocks
    WHERE is_active = TRUE
    ORDER BY random()
    LIMIT GREATEST(p_orders, 1)
  LOOP
    v_price := COALESCE(v_stock.last_price, 10);

    -- ✅ Get order book (NO FOR UPDATE here)
    SELECT
      COALESCE(SUM(CASE WHEN side = 'buy' THEN quantity - filled_quantity END), 0),
      COALESCE(SUM(CASE WHEN side = 'sell' THEN quantity - filled_quantity END), 0)
    INTO v_bid_qty, v_ask_qty
    FROM orders
    WHERE stock_id = v_stock.stock_id
      AND status IN ('open','partial');

    -- imbalance
    IF (v_bid_qty + v_ask_qty) > 0 THEN
      v_imbalance := (v_bid_qty - v_ask_qty) / (v_bid_qty + v_ask_qty);
    ELSE
      v_imbalance := 0;
    END IF;

    -- activity (last 24h trades)
    SELECT COUNT(*) INTO v_activity
    FROM trades
    WHERE stock_id = v_stock.stock_id
      AND executed_at >= NOW() - INTERVAL '24 hours';

    -- fair price smoothing
    SELECT COALESCE(AVG(close_price), v_price)
    INTO v_price
    FROM (
      SELECT close_price
      FROM price_history
      WHERE stock_id = v_stock.stock_id
      ORDER BY recorded_at DESC
      LIMIT 10
    ) t;

    -- dynamic spread
    v_spread := GREATEST(
      v_price * (
        CASE
          WHEN v_activity >= 20 THEN 0.0005
          WHEN v_activity >= 5 THEN 0.001
          ELSE 0.003
        END
      ),
      0.01
    );

    -- number of levels
    v_levels := CASE
      WHEN v_activity >= 20 THEN 5
      WHEN v_activity >= 5 THEN 4
      ELSE 3
    END;

    -- ensure seller has inventory
    INSERT INTO portfolios (user_id, stock_id, quantity, average_price)
    VALUES (v_seller_bot_id, v_stock.stock_id, 200000, v_price)
    ON CONFLICT (user_id, stock_id) DO UPDATE
    SET quantity = GREATEST(portfolios.quantity, 200000);

    -- 🧠 MARKET MAKING LADDER
    FOR i IN 1..v_levels LOOP
      v_quantity := (random() * 300 + 50)::INT;

      v_buy_limit := ROUND(
        v_price - (v_spread * i * (1 + GREATEST(0, -v_imbalance))),
        4
      );

      v_sell_limit := ROUND(
        v_price + (v_spread * i * (1 + GREATEST(0, v_imbalance))),
        4
      );

      PERFORM place_order(
        v_buyer_bot_id,
        v_stock.stock_id,
        'limit',
        'buy',
        v_quantity,
        v_buy_limit,
        NULL
      );

      PERFORM place_order(
        v_seller_bot_id,
        v_stock.stock_id,
        'limit',
        'sell',
        v_quantity,
        v_sell_limit,
        NULL
      );

      v_created := v_created + 2;
    END LOOP;

    -- 🎯 OCCASIONAL REAL TRADE (not forced every tick)
    IF random() < 0.2 THEN
      v_quantity := (random() * 200 + 100)::INT;

      PERFORM place_order(
        v_buyer_bot_id,
        v_stock.stock_id,
        'limit',
        'buy',
        v_quantity,
        ROUND(v_price + (v_spread * 0.2), 4),
        NULL
      );

      PERFORM place_order(
        v_seller_bot_id,
        v_stock.stock_id,
        'limit',
        'sell',
        v_quantity,
        ROUND(v_price - (v_spread * 0.2), 4),
        NULL
      );

      v_created := v_created + 2;
    END IF;

  END LOOP;

  RETURN v_created;
END;
$$ LANGUAGE plpgsql;