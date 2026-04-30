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
  v_factor NUMERIC;
  v_old_price NUMERIC;
  v_new_price NUMERIC;
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
    v_old_price := COALESCE(v_stock.last_price, 1);
    v_factor := 1 + ((random() - 0.5) / 20);
    v_new_price := GREATEST(0.01, ROUND((v_old_price * v_factor)::numeric, 4));

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

CREATE OR REPLACE FUNCTION simulate_market_activity(p_orders INT DEFAULT 3)
RETURNS INT AS $$
DECLARE
  v_buyer_bot_id INT;
  v_seller_bot_id INT;
  v_order RECORD;
  v_stock RECORD;
  v_price NUMERIC;
  v_spread NUMERIC;
  v_bid_qty NUMERIC;
  v_ask_qty NUMERIC;
  v_imbalance NUMERIC;
  v_activity NUMERIC;
  v_aggression NUMERIC;
  v_buy_limit NUMERIC;
  v_sell_limit NUMERIC;
  v_cross_sell_limit NUMERIC;
  v_cross_buy_limit NUMERIC;
  v_quantity INT;
  v_levels INT;
  i INT;
  v_created INT := 0;
  BEGIN
    SELECT user_id INTO v_buyer_bot_id
    FROM users
    WHERE username = 'liquidity_bot';

  SELECT user_id INTO v_seller_bot_id
  FROM users
  WHERE username = 'liquidity_seller';

    IF v_buyer_bot_id IS NULL OR v_seller_bot_id IS NULL THEN
      RAISE EXCEPTION 'Liquidity bot users are missing';
    END IF;

    -- Synthetic market makers: keep them funded so they can keep providing liquidity.
    UPDATE wallets
    SET cash_balance = GREATEST(cash_balance, 5000000),
        reserved_balance = 0,
        updated_at = NOW()
    WHERE user_id = v_buyer_bot_id;

    UPDATE wallets
    SET cash_balance = GREATEST(cash_balance, 2500000),
        reserved_balance = 0,
        updated_at = NOW()
    WHERE user_id = v_seller_bot_id;

    FOR v_stock IN
      SELECT order_id, user_id
      FROM orders
    WHERE user_id IN (v_buyer_bot_id, v_seller_bot_id)
      AND status IN ('open','partial')
    ORDER BY created_at ASC
  LOOP
    PERFORM cancel_order(v_stock.order_id, v_stock.user_id);
  END LOOP;

  FOR v_order IN
    SELECT
      o.order_id,
      o.user_id,
      o.stock_id,
      s.ticker,
      o.side,
      o.order_type,
      o.quantity - o.filled_quantity AS remaining_quantity,
      COALESCE(o.limit_price, s.last_price, (
        SELECT close_price
        FROM price_history ph
        WHERE ph.stock_id = o.stock_id
        ORDER BY ph.recorded_at DESC
        LIMIT 1
      )) AS ref_price
    FROM orders o
    JOIN stocks s ON s.stock_id = o.stock_id
    WHERE o.status IN ('open','partial')
      AND o.user_id NOT IN (v_buyer_bot_id, v_seller_bot_id)
    ORDER BY o.created_at ASC
    LIMIT GREATEST(p_orders * 4, 4)
  LOOP
    v_quantity := GREATEST(v_order.remaining_quantity, 1);
    v_price := COALESCE(v_order.ref_price, 1);
    v_spread := GREATEST(v_price * 0.0015, 0.01);
    v_cross_sell_limit := GREATEST(v_price - (v_spread * 0.25), 0.01);
    v_cross_buy_limit := GREATEST(v_price + (v_spread * 0.25), 0.01);

    IF v_order.side = 'buy' THEN
      v_sell_limit := v_cross_sell_limit;

      PERFORM place_order(
        v_seller_bot_id,
        v_order.stock_id,
        'limit'::order_type,
        'sell'::order_side,
        v_quantity,
        v_sell_limit,
        NULL
      );
    ELSE
      v_buy_limit := v_cross_buy_limit;

      PERFORM place_order(
        v_buyer_bot_id,
        v_order.stock_id,
        'limit'::order_type,
        'buy'::order_side,
        v_quantity,
        v_buy_limit,
        NULL
      );
    END IF;

    v_created := v_created + 1;
  END LOOP;

  FOR v_stock IN
        SELECT s.stock_id,
               s.ticker,
               s.last_price,
               COALESCE(book.bid_qty, 0) AS bid_qty,
             COALESCE(book.ask_qty, 0) AS ask_qty,
             COALESCE(trd.activity_24h, 0) AS activity_24h
      FROM stocks s
      LEFT JOIN LATERAL (
        SELECT
          SUM(CASE WHEN side = 'buy' THEN quantity - filled_quantity ELSE 0 END) AS bid_qty,
          SUM(CASE WHEN side = 'sell' THEN quantity - filled_quantity ELSE 0 END) AS ask_qty
      FROM orders o
      WHERE o.stock_id = s.stock_id
        AND o.status IN ('open','partial')
    ) book ON TRUE
    LEFT JOIN LATERAL (
      SELECT COUNT(*) AS activity_24h
      FROM trades t
      WHERE t.stock_id = s.stock_id
        AND t.executed_at >= NOW() - INTERVAL '24 hours'
    ) trd ON TRUE
    WHERE s.is_active = TRUE
    ORDER BY random()
    LIMIT GREATEST(p_orders, 1)
  LOOP
    v_price := COALESCE(v_stock.last_price, 1);
    v_bid_qty := COALESCE(v_stock.bid_qty, 0);
    v_ask_qty := COALESCE(v_stock.ask_qty, 0);
    v_activity := COALESCE(v_stock.activity_24h, 0);
    v_imbalance := v_bid_qty - v_ask_qty;
    v_aggression := LEAST(0.5, GREATEST(0.1, 0.2 + (v_activity * 0.01)));

    v_spread := GREATEST(v_price * CASE
        WHEN v_activity >= 20 THEN 0.0005
        WHEN v_activity >= 5 THEN 0.001
        ELSE 0.0025
      END, 0.01);

    IF v_imbalance > 0 THEN
      v_spread := v_spread * 0.85;
    ELSIF v_imbalance < 0 THEN
      v_spread := v_spread * 1.15;
    END IF;

      v_levels := CASE
        WHEN v_activity >= 20 THEN 5
        WHEN v_activity >= 5 THEN 4
        ELSE 3
      END;

      -- Keep the synthetic seller stocked so the simulator can keep generating liquidity.
      UPDATE portfolios
      SET quantity = GREATEST(quantity, 250000),
          average_price = COALESCE(average_price, v_price)
      WHERE user_id = v_seller_bot_id
        AND stock_id = v_stock.stock_id;

      IF NOT FOUND THEN
        INSERT INTO portfolios (user_id, stock_id, quantity, locked_quantity, average_price)
        VALUES (v_seller_bot_id, v_stock.stock_id, 250000, 0, v_price)
        ON CONFLICT (user_id, stock_id) DO UPDATE
        SET quantity = GREATEST(portfolios.quantity, EXCLUDED.quantity),
            average_price = COALESCE(portfolios.average_price, EXCLUDED.average_price);
      END IF;

      FOR i IN 1..v_levels LOOP
        v_quantity := GREATEST(((random() * 400)::INT + 50), 50);
      v_buy_limit := ROUND((v_price - (v_spread * i))::numeric, 4);
      v_sell_limit := ROUND((v_price + (v_spread * i))::numeric, 4);

      IF v_imbalance > 0 THEN
        v_sell_limit := ROUND((v_price + (v_spread * (i - 0.35)))::numeric, 4);
      ELSIF v_imbalance < 0 THEN
        v_buy_limit := ROUND((v_price - (v_spread * (i - 0.35)))::numeric, 4);
      END IF;

      PERFORM place_order(
        v_buyer_bot_id,
        v_stock.stock_id,
        'limit'::order_type,
        'buy'::order_side,
        v_quantity,
        v_buy_limit,
        NULL
      );
      PERFORM place_order(
        v_seller_bot_id,
        v_stock.stock_id,
        'limit'::order_type,
        'sell'::order_side,
        v_quantity,
        v_sell_limit,
        NULL
      );

      v_created := v_created + 2;
    END LOOP;

    -- Create one crossing pair so the bots execute against each other and move price naturally.
    v_quantity := GREATEST(((random() * 300)::INT + 100), 100);
    v_buy_limit := ROUND((v_price + (v_spread * v_aggression))::numeric, 4);
    v_sell_limit := ROUND((v_price - (v_spread * v_aggression))::numeric, 4);

    PERFORM place_order(
      v_buyer_bot_id,
      v_stock.stock_id,
      'limit'::order_type,
      'buy'::order_side,
      v_quantity,
      v_buy_limit,
      NULL
    );
    PERFORM place_order(
      v_seller_bot_id,
      v_stock.stock_id,
      'limit'::order_type,
      'sell'::order_side,
      v_quantity,
      v_sell_limit,
      NULL
    );
    v_created := v_created + 2;
  END LOOP;

  RETURN v_created;
END;
$$ LANGUAGE plpgsql;
