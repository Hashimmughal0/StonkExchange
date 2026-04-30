const app = require('./app');
const pool = require('./config/db');
const dotenv = require('dotenv');
const { startMarketSimulator, stopMarketSimulator } = require('./jobs/marketSimulator');

dotenv.config();

const PORT = process.env.PORT || 4000;

app.listen(PORT, () => {
  console.log(`Server listening on http://localhost:${PORT}`);
  startMarketSimulator();
});

process.on('SIGINT', async () => {
  await stopMarketSimulator();
  await pool.end();
  process.exit();
});
