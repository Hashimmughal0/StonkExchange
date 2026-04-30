# StockDB Exchange Backend

## Database setup
1. Create the database and enable extensions, e.g. CREATE DATABASE stonkexchange;.
2. Run the schema, view, procedure, and trigger scripts in order:
   `sh
   psql  -f db/schema.sql
   psql  -f db/views.sql
   psql  -f db/procedures.sql
   psql  -f db/triggers.sql
   psql  -f db/seed.sql
   `
3. Adjust URLs, credentials, and secrets in .env before starting the server.

## Backend
1. Copy .env.example into .env and fill in DATABASE_URL, JWT_SECRET, and optional PORT.
2. Install npm dependencies:
   `sh
   npm install
   `
3. Start the server:
   `sh
   npm start
   `

The Express API exposes the following groups of routes:
- /api/auth for registration, login, logout, and me lookup.
- /api/stocks for market data (listing, detail, order book, trades, chart).
- /api/orders for placing, listing, viewing, and cancelling orders.
- /api/wallet for wallet/portfolio inspection and deposit/withdrawal actions.
- /api/admin for stock management, audit log, user stats, and system overview (admin-only).

All business rules (order matching, wallet adjustments, auditing) execute inside the database via stored procedures, views, and triggers defined in the db folder.

## Notes
- The seeded users share one hashed password placeholder; you can re-seed with your own bcrypt hash if needed.
- This repository currently lacks installed 
ode_modules because 
pm install timed out in this environment; run 
pm install locally before starting the server.
\nSeeded users (alice, bob, admin) all use the plaintext password password.
