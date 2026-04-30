const express = require('express');
const pool = require('../config/db');
const { authenticate, requireAdmin } = require('../middleware/auth');

const router = express.Router();

router.use(authenticate, requireAdmin);

router.post('/stocks', async (req, res) => {
  const { ticker, companyName, initialPrice, totalShares } = req.body;
  if (!ticker || !companyName || initialPrice == null || totalShares == null) {
    return res.status(400).json({ message: 'Missing stock data' });
  }

  try {
    const { rows } = await pool.query(
      `
      INSERT INTO stocks (ticker, company_name, last_price, total_shares)
      VALUES ($1, $2, $3, $4)
      RETURNING *
      `,
      [ticker.toUpperCase(), companyName, Number(initialPrice), Number(totalShares)]
    );
    res.status(201).json({ data: rows[0] });
  } catch (err) {
    console.error(err);
    res.status(400).json({ message: err.message });
  }
});

router.patch('/stocks/:id', async (req, res) => {
  const { id } = req.params;
  const fields = [];
  const values = [];
  const allowed = ['company_name', 'last_price', 'total_shares', 'is_active'];

  Object.entries(req.body).forEach(([key, value]) => {
    if (allowed.includes(key)) {
      fields.push(`${key} = $${fields.length + 1}`);
      values.push(key === 'last_price' || key === 'total_shares' ? Number(value) : value);
    }
  });

  if (!fields.length) {
    return res.status(400).json({ message: 'No fields to update' });
  }

  values.push(id);
  const query = `UPDATE stocks SET ${fields.join(', ')} WHERE stock_id = $${values.length} RETURNING *`;

  try {
    const { rows } = await pool.query(query, values);
    if (!rows.length) {
      return res.status(404).json({ message: 'Stock not found' });
    }
    res.json({ data: rows[0] });
  } catch (err) {
    console.error(err);
    res.status(400).json({ message: err.message });
  }
});

router.get('/users', async (req, res) => {
  const { rows } = await pool.query(`
    SELECT u.user_id, u.username, u.email, u.role, u.created_at,
           w.cash_balance, w.reserved_balance,
           (SELECT COUNT(*) FROM orders o WHERE o.user_id = u.user_id) AS order_count
    FROM users u
    LEFT JOIN wallets w ON w.user_id = u.user_id
    ORDER BY u.created_at DESC
  `);
  res.json({ data: rows });
});

router.get('/audit-log', async (req, res) => {
  const limit = Math.min(100, Number.parseInt(req.query.limit, 10) || 50);
  const { rows } = await pool.query(
    'SELECT * FROM audit_log ORDER BY created_at DESC LIMIT $1',
    [limit]
  );
  res.json({ data: rows });
});

router.get('/system', async (req, res) => {
  const { rows } = await pool.query(`
    SELECT
      (SELECT COUNT(*) FROM users) AS users,
      (SELECT COUNT(*) FROM stocks) AS stocks,
      (SELECT COUNT(*) FROM orders) AS orders,
      (SELECT COUNT(*) FROM trades) AS trades,
      (SELECT COUNT(*) FROM orders WHERE status IN ('open','partial')) AS open_orders,
      (SELECT COALESCE(SUM(cash_balance + reserved_balance), 0) FROM wallets) AS cash_total
  `);

  res.json({ data: rows[0] });
});

router.get('/simulator-orders', async (req, res) => {
  const limit = Math.min(100, Number.parseInt(req.query.limit, 10) || 20);
  const { rows } = await pool.query(
    `
    SELECT
      o.order_id,
      u.username,
      o.side,
      o.order_type,
      o.quantity,
      o.filled_quantity,
      o.limit_price,
      o.status,
      o.created_at
    FROM orders o
    JOIN users u ON u.user_id = o.user_id
    WHERE u.username IN ('liquidity_bot', 'liquidity_seller')
    ORDER BY o.created_at DESC
    LIMIT $1
    `,
    [limit]
  );

  res.json({ data: rows });
});

module.exports = router;
