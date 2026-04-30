const express = require('express');
const pool = require('../config/db');

const router = express.Router();

async function findStockByIdentifier(identifier) {
  const normalized = String(identifier).toUpperCase();
  const isNumeric = /^\d+$/.test(String(identifier));
  const query = isNumeric
    ? 'SELECT stock_id, ticker, company_name, last_price, total_shares, is_active, created_at FROM stocks WHERE stock_id = $1'
    : 'SELECT stock_id, ticker, company_name, last_price, total_shares, is_active, created_at FROM stocks WHERE ticker = $1';
  const params = [isNumeric ? Number(identifier) : normalized];
  const { rows } = await pool.query(query, params);
  return rows[0] || null;
}

router.get('/', async (req, res) => {
  const { rows } = await pool.query(
    'SELECT stock_id, ticker, company_name, last_price, total_shares, is_active FROM stocks WHERE is_active = TRUE ORDER BY ticker'
  );
  res.json({ data: rows });
});

router.get('/:ticker', async (req, res) => {
  const stock = await findStockByIdentifier(req.params.ticker);
  if (!stock) {
    return res.status(404).json({ message: 'Stock not found' });
  }
  res.json({ data: stock });
});

router.get('/id/:id', async (req, res) => {
  const stock = await findStockByIdentifier(req.params.id);
  if (!stock) {
    return res.status(404).json({ message: 'Stock not found' });
  }
  res.json({ data: stock });
});

router.get('/:ticker/orderbook', async (req, res) => {
  const { ticker } = req.params;
  const side = req.query.side;

  let query = `
    SELECT side, limit_price, total_quantity, order_count
    FROM v_order_book
    WHERE ticker = $1
  `;
  const params = [ticker.toUpperCase()];

  if (side === 'buy' || side === 'sell') {
    query += ' AND side = $2';
    params.push(side);
  }

  query += ' ORDER BY side, limit_price DESC';

  const { rows } = await pool.query(query, params);
  res.json({ data: rows });
});

router.get('/:ticker/trades', async (req, res) => {
  const { ticker } = req.params;
  const { rows } = await pool.query(
    `
    SELECT trade_id, ticker, price, quantity, executed_at
    FROM v_trade_history
    WHERE ticker = $1
    ORDER BY executed_at DESC
    LIMIT 50
    `,
    [ticker.toUpperCase()]
  );

  res.json({ data: rows });
});

router.get('/:ticker/chart', async (req, res) => {
  const { ticker } = req.params;
  const limit = Math.min(500, Number(req.query.limit) || 100);
  const { rows } = await pool.query(
    `
    SELECT ph.recorded_at, ph.open_price, ph.high_price, ph.low_price, ph.close_price, ph.volume
    FROM price_history ph
    JOIN stocks s ON s.stock_id = ph.stock_id
    WHERE s.ticker = $1
    ORDER BY ph.recorded_at DESC
    LIMIT $2
    `,
    [ticker.toUpperCase(), limit]
  );

  res.json({ data: rows.reverse() });
});

router.get('/prices/:id', async (req, res) => {
  const limit = Math.min(500, Number(req.query.limit) || 100);
  const stock = await findStockByIdentifier(req.params.id);
  if (!stock) {
    return res.status(404).json({ message: 'Stock not found' });
  }

  const { rows } = await pool.query(
    `
    SELECT ph.recorded_at, ph.open_price, ph.high_price, ph.low_price, ph.close_price, ph.volume
    FROM price_history ph
    WHERE ph.stock_id = $1
    ORDER BY ph.recorded_at DESC
    LIMIT $2
    `,
    [stock.stock_id, limit]
  );

  res.json({ data: rows.reverse() });
});

module.exports = router;
