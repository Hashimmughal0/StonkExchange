-- Triggers and supporting functions

CREATE OR REPLACE FUNCTION trg_match_orders()
RETURNS TRIGGER AS $$
BEGIN
  PERFORM match_orders(NEW.stock_id);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER after_order_insert
AFTER INSERT ON orders
FOR EACH ROW EXECUTE FUNCTION trg_match_orders();

CREATE OR REPLACE FUNCTION trg_trade_post()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE stocks
  SET last_price = NEW.price
  WHERE stock_id = NEW.stock_id;

  INSERT INTO price_history (
    stock_id,
    recorded_at,
    open_price,
    high_price,
    low_price,
    close_price,
    volume
  )
  VALUES (NEW.stock_id, NOW(), NEW.price, NEW.price, NEW.price, NEW.price, NEW.quantity);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER after_trade_insert
AFTER INSERT ON trades
FOR EACH ROW EXECUTE FUNCTION trg_trade_post();

CREATE OR REPLACE FUNCTION trg_audit_order()
RETURNS TRIGGER AS $$
BEGIN
  PERFORM log_audit(
    'orders',
    NEW.order_id,
    NEW.user_id,
    TG_OP::TEXT,
    jsonb_build_object(
      'status', NEW.status,
      'filled', NEW.filled_quantity,
      'quantity', NEW.quantity
    )
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER audit_order_changes
AFTER INSERT OR UPDATE ON orders
FOR EACH ROW EXECUTE FUNCTION trg_audit_order();

CREATE OR REPLACE FUNCTION trg_audit_trade()
RETURNS TRIGGER AS $$
DECLARE
  v_details JSONB;
BEGIN
  v_details := jsonb_build_object(
    'buy_order', NEW.buy_order_id,
    'sell_order', NEW.sell_order_id,
    'qty', NEW.quantity,
    'price', NEW.price
  );
  PERFORM log_audit('trades', NEW.trade_id, NULL, 'executed', v_details);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER audit_trade_execution
AFTER INSERT ON trades
FOR EACH ROW EXECUTE FUNCTION trg_audit_trade();

CREATE OR REPLACE FUNCTION trg_audit_wallet()
RETURNS TRIGGER AS $$
DECLARE
  v_details JSONB;
BEGIN
  v_details := jsonb_build_object(
    'cash_balance', NEW.cash_balance,
    'reserved_balance', NEW.reserved_balance
  );
  PERFORM log_audit('wallets', NEW.wallet_id, NEW.user_id, 'updated', v_details);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER audit_wallet_changes
AFTER UPDATE ON wallets
FOR EACH ROW EXECUTE FUNCTION trg_audit_wallet();
