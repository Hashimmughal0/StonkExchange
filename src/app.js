const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');

const authRoutes = require('./routes/auth');
const stockRoutes = require('./routes/stocks');
const orderRoutes = require('./routes/orders');
const walletRoutes = require('./routes/wallet');
const adminRoutes = require('./routes/admin');
const pool = require('./config/db');

const app = express();

app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(morgan('tiny'));

app.use('/api/auth', authRoutes);
app.use('/api/stocks', stockRoutes);
app.use('/api/orders', orderRoutes);
app.use('/api/wallet', walletRoutes);
app.use('/api/admin', adminRoutes);

app.get('/health', async (req, res, next) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok', database: 'up' });
  } catch (err) {
    next(err);
  }
});

app.use((req, res) => {
  res.status(404).json({ message: 'Route not found' });
});

app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ message: 'Internal server error' });
});

module.exports = app;
