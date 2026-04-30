const express = require('express');
const bcrypt = require('bcryptjs');
const pool = require('../config/db');
const { generateToken } = require('../utils/jwt');
const { authenticate } = require('../middleware/auth');

const router = express.Router();

function buildUser(row) {
  return {
    id: row.user_id,
    username: row.username,
    email: row.email,
    role: row.role,
    createdAt: row.created_at
  };
}

router.post('/register', async (req, res) => {
  const { username, email, password } = req.body;
  if (!username || !email || !password) {
    return res.status(400).json({ message: 'Missing username, email or password' });
  }

  const hashed = await bcrypt.hash(password, 12);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const userRes = await client.query(
      'INSERT INTO users (username, email, password_hash) VALUES ($1, $2, $3) RETURNING user_id, username, email, role, created_at',
      [username, email, hashed]
    );
    const user = userRes.rows[0];
    await client.query('INSERT INTO wallets (user_id, cash_balance) VALUES ($1, $2)', [user.user_id, 10000]);

    const token = generateToken({ userId: user.user_id, role: user.role });
    const expiresAt = new Date(Date.now() + 60 * 60 * 1000);
    await client.query('INSERT INTO sessions (token, user_id, expires_at) VALUES ($1, $2, $3)', [token, user.user_id, expiresAt]);
    await client.query('COMMIT');

    return res.status(201).json({ token, user: buildUser(user) });
  } catch (err) {
    await client.query('ROLLBACK');
    if (err.code === '23505') {
      return res.status(409).json({ message: 'Username or email already taken' });
    }
    console.error(err);
    return res.status(500).json({ message: 'Unable to create user' });
  } finally {
    client.release();
  }
});

router.post('/login', async (req, res) => {
  const { username, password } = req.body;
  if (!username || !password) {
    return res.status(400).json({ message: 'Missing credentials' });
  }

  const { rows } = await pool.query(
    'SELECT user_id, username, email, password_hash, role FROM users WHERE username = $1',
    [username]
  );
  const user = rows[0];
  if (!user) {
    return res.status(401).json({ message: 'Invalid credentials' });
  }
  const match = await bcrypt.compare(password, user.password_hash);
  if (!match) {
    return res.status(401).json({ message: 'Invalid credentials' });
  }

  const token = generateToken({ userId: user.user_id, role: user.role });
  const expiresAt = new Date(Date.now() + 60 * 60 * 1000);
  await pool.query('INSERT INTO sessions (token, user_id, expires_at) VALUES ($1, $2, $3)', [token, user.user_id, expiresAt]);

  return res.json({ token, user: buildUser(user) });
});

router.post('/logout', authenticate, async (req, res) => {
  await pool.query('DELETE FROM sessions WHERE token = $1', [req.user.token]);
  res.status(204).send();
});

router.get('/me', authenticate, async (req, res) => {
  const { rows } = await pool.query('SELECT user_id, username, email, role, created_at FROM users WHERE user_id = $1', [req.user.userId]);
  if (!rows.length) {
    return res.status(404).json({ message: 'User not found' });
  }
  res.json({ user: buildUser(rows[0]) });
});

module.exports = router;
