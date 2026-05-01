const express = require('express');
const pool = require('../config/db');
const { authenticate } = require('../middleware/auth');

const router = express.Router();

function normalizeOrderType(orderType) {
  const value = String(orderType || '').toLowerCase();
  if (!['market', 'limit', 'stop_loss'].includes(value)) {
    return null;
  }
  return value;
}

function normalizeSide(side) {
  const value = String(side || '').toLowerCase();
  if (!['buy', 'sell'].includes(value)) {
    return null;
  }
  return value;
}

router.post('/', authenticate, async (req, res) => {
  const { ticker, orderType, side, quantity, limitPrice, stopPrice } = req.body;
  if (!ticker || !orderType || !side || quantity == null) {
    return res.status(400).json({ message: 'Missing order fields' });
  }

  const normalizedOrderType = normalizeOrderType(orderType);
  const normalizedSide = normalizeSide(side);
  if (!normalizedOrderType || !normalizedSide) {
    return res.status(400).json({ message: 'Invalid order type or side' });
  }

  const stockRes = await pool.query(
    'SELECT stock_id FROM stocks WHERE ticker = $1 AND is_active = TRUE',
    [ticker.toUpperCase()]
  );
  if (!stockRes.rows.length) {
    return res.status(404).json({ message: 'Stock not found' });
  }

  const numericQuantity = Number(quantity);
  const numericLimitPrice = limitPrice == null || limitPrice === '' ? null : Number(limitPrice);
  const numericStopPrice = stopPrice == null || stopPrice === '' ? null : Number(stopPrice);

  try {
    const spRes = await pool.query(
      'SELECT place_order($1, $2, $3::order_type, $4::order_side, $5, $6, $7) AS order_id',
      [
        req.user.userId,
        stockRes.rows[0].stock_id,
        normalizedOrderType,
        normalizedSide,
        numericQuantity,
        numericLimitPrice,
        numericStopPrice
      ]
    );
    return res.status(201).json({ orderId: spRes.rows[0].order_id });
  } catch (err) {
    console.error(err);
    return res.status(400).json({ message: err.message });
  }
});

router.get('/', authenticate, async (req, res) => {
  const { rows } = await pool.query(
    'SELECT * FROM v_all_orders WHERE user_id = $1 ORDER BY created_at DESC',
    [req.user.userId]
  );
  res.json({ data: rows });
});

router.get('/:id', authenticate, async (req, res) => {
  const { id } = req.params;
  const { rows } = await pool.query(
    'SELECT * FROM v_all_orders WHERE order_id = $1 AND user_id = $2',
    [id, req.user.userId]
  );

  if (!rows.length) {
    return res.status(404).json({ message: 'Order not found' });
  }

  res.json({ data: rows[0] });
});

router.delete('/:id', authenticate, async (req, res) => {
  const { id } = req.params;
  try {
    await pool.query('SELECT cancel_order($1, $2)', [id, req.user.userId]);
    res.status(204).send();
  } catch (err) {
    console.error(err);
    res.status(400).json({ message: err.message });
  }
});

module.exports = router;
