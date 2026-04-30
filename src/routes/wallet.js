const express = require('express');
const pool = require('../config/db');
const { authenticate } = require('../middleware/auth');

const router = express.Router();

router.use(authenticate);

router.get('/portfolio', async (req, res) => {
  const { rows } = await pool.query(
    'SELECT * FROM v_user_portfolio WHERE user_id = $1 ORDER BY ticker',
    [req.user.userId]
  );
  res.json({ data: rows });
});

router.get('/wallet', async (req, res) => {
  const { rows } = await pool.query(
    'SELECT wallet_id, cash_balance, reserved_balance, updated_at FROM wallets WHERE user_id = $1',
    [req.user.userId]
  );
  res.json({ data: rows[0] || null });
});

router.post('/deposit', async (req, res) => {
  const amount = Number(req.body.amount);
  if (!amount || amount <= 0) {
    return res.status(400).json({ message: 'Amount must be positive' });
  }

  try {
    await pool.query('SELECT deposit_funds($1, $2)', [req.user.userId, amount]);
    res.status(204).send();
  } catch (err) {
    console.error(err);
    res.status(400).json({ message: err.message });
  }
});

router.post('/withdraw', async (req, res) => {
  const amount = Number(req.body.amount);
  if (!amount || amount <= 0) {
    return res.status(400).json({ message: 'Amount must be positive' });
  }

  try {
    await pool.query('SELECT withdraw_funds($1, $2)', [req.user.userId, amount]);
    res.status(204).send();
  } catch (err) {
    console.error(err);
    res.status(400).json({ message: err.message });
  }
});

module.exports = router;
