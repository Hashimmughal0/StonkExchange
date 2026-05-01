const pool = require('../config/db');

let timer = null;
let running = false;

async function runLiquidityCycle() {
  await pool.query('SELECT simulate_liquidity_engine($1)', [
    Number(process.env.MARKET_SIMULATOR_CYCLES || 1)
  ]);
}

function startMarketSimulator() {
  if (timer || process.env.MARKET_SIMULATOR !== 'true') {
    return;
  }

  const intervalMs = Number(process.env.MARKET_SIMULATOR_INTERVAL_MS || 5000);

  timer = setInterval(async () => {
    if (running) {
      return;
    }

    running = true;
    try {
      await runLiquidityCycle();
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
