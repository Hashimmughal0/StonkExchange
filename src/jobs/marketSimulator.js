const pool = require('../config/db');

let timer = null;
let running = false;

function startMarketSimulator() {
  if (timer || process.env.MARKET_SIMULATOR !== 'true') {
    return;
  }

  const intervalMs = Number(process.env.MARKET_SIMULATOR_INTERVAL_MS || 50);

  timer = setInterval(async () => {
    if (running) {
      return;
    }

    running = true;
    try {
      await pool.query('SELECT simulate_market_tick($1)', [Number(process.env.MARKET_SIMULATOR_MOVES || 5)]);
      await pool.query('SELECT simulate_market_activity($1)', [Number(process.env.MARKET_SIMULATOR_ORDERS || 3)]);
    } catch (err) {
      console.error('Market simulator tick failed:', err.message);
    } finally {
      running = false;
    }
  }, intervalMs);
}

async function stopMarketSimulator() {
  if (timer) {
    clearInterval(timer);
    timer = null;
  }
  running = false;
}

module.exports = { startMarketSimulator, stopMarketSimulator };
