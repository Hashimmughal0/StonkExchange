CREATE TABLE Users (
    user_id         INT             NOT NULL IDENTITY(1,1),
    name            VARCHAR(100)    NOT NULL,
    email           VARCHAR(150)    NOT NULL,
    password_hash   VARCHAR(255)    NOT NULL,
    balance         NUMERIC(18, 2)  NOT NULL DEFAULT 0.00,
    locked_balance  NUMERIC(18, 2)  NOT NULL DEFAULT 0.00,
    created_at      DATETIME        NOT NULL DEFAULT GETDATE(),

    CONSTRAINT pk_users             PRIMARY KEY (user_id),
    CONSTRAINT uq_users_email       UNIQUE      (email),
    CONSTRAINT chk_users_balance    CHECK (balance >= 0),
    CONSTRAINT chk_users_locked_bal CHECK (locked_balance >= 0)
);
CREATE TABLE Assets (
    asset_id        INT             NOT NULL IDENTITY(1,1),
    symbol          VARCHAR(10)     NOT NULL,
    company_name    VARCHAR(200)    NOT NULL,
    last_price      NUMERIC(18, 4)  NOT NULL DEFAULT 0.0000,
    is_active       BIT             NOT NULL DEFAULT 1,
    created_at      DATETIME        NOT NULL DEFAULT GETDATE(),

    CONSTRAINT pk_assets         PRIMARY KEY (asset_id),
    CONSTRAINT uq_assets_symbol  UNIQUE      (symbol)
);
CREATE TABLE Orders (
    order_id           INT             NOT NULL IDENTITY(1,1),
    user_id            INT             NOT NULL,
    asset_id           INT             NOT NULL,
    order_type         VARCHAR(4)      NOT NULL,
    order_style        VARCHAR(6)      NOT NULL,
    price              NUMERIC(18, 4)  NULL,
    quantity           INT             NOT NULL,
    remaining_quantity INT             NOT NULL,
    status             VARCHAR(9)      NOT NULL DEFAULT 'OPEN',
    created_at         DATETIME        NOT NULL DEFAULT GETDATE(),

    CONSTRAINT pk_orders              PRIMARY KEY (order_id),
    CONSTRAINT fk_orders_user         FOREIGN KEY (user_id)  REFERENCES Users  (user_id),
    CONSTRAINT fk_orders_asset        FOREIGN KEY (asset_id) REFERENCES Assets (asset_id),
    CONSTRAINT chk_order_type         CHECK (order_type  IN ('BUY',  'SELL')),
    CONSTRAINT chk_order_style        CHECK (order_style IN ('LIMIT','MARKET')),
    CONSTRAINT chk_order_status       CHECK (status      IN ('OPEN', 'PARTIAL', 'FILLED', 'CANCELLED')),
    CONSTRAINT chk_order_quantity     CHECK (quantity > 0),
    CONSTRAINT chk_remaining_qty      CHECK (remaining_quantity >= 0),
    CONSTRAINT chk_limit_price        CHECK (order_style = 'MARKET' OR price IS NOT NULL)
);
CREATE TABLE Trades (
    trade_id      INT             NOT NULL IDENTITY(1,1),
    buy_order_id  INT             NOT NULL,
    sell_order_id INT             NOT NULL,
    asset_id      INT             NOT NULL,
    price         NUMERIC(18, 4)  NOT NULL,
    quantity      INT             NOT NULL,
    executed_at   DATETIME        NOT NULL DEFAULT GETDATE(),

    CONSTRAINT pk_trades            PRIMARY KEY (trade_id),
    CONSTRAINT fk_trades_buy_order  FOREIGN KEY (buy_order_id)  REFERENCES Orders (order_id),
    CONSTRAINT fk_trades_sell_order FOREIGN KEY (sell_order_id) REFERENCES Orders (order_id),
    CONSTRAINT fk_trades_asset      FOREIGN KEY (asset_id)      REFERENCES Assets (asset_id),
    CONSTRAINT chk_trades_quantity  CHECK (quantity > 0)
);
CREATE TABLE Portfolio_Holdings (
    user_id         INT             NOT NULL,
    asset_id        INT             NOT NULL,
    quantity        INT             NOT NULL DEFAULT 0,
    locked_quantity INT             NOT NULL DEFAULT 0,
    average_price   NUMERIC(18, 4)  NOT NULL DEFAULT 0.0000,

    CONSTRAINT pk_portfolio         PRIMARY KEY (user_id, asset_id),
    CONSTRAINT fk_portfolio_user    FOREIGN KEY (user_id)  REFERENCES Users  (user_id),
    CONSTRAINT fk_portfolio_asset   FOREIGN KEY (asset_id) REFERENCES Assets (asset_id),
    CONSTRAINT chk_portfolio_qty    CHECK (quantity >= 0),
    CONSTRAINT chk_portfolio_locked CHECK (locked_quantity >= 0)
);

CREATE TABLE Price_History (
    price_id       INT             NOT NULL IDENTITY(1,1),
    asset_id       INT             NOT NULL,
    open_price     NUMERIC(18, 4)  NOT NULL,
    high_price     NUMERIC(18, 4)  NOT NULL,
    low_price      NUMERIC(18, 4)  NOT NULL,
    close_price    NUMERIC(18, 4)  NOT NULL,
    volume         BIGINT          NOT NULL DEFAULT 0,
    time_interval  DATETIME        NOT NULL,

    CONSTRAINT pk_price_history       PRIMARY KEY (price_id),
    CONSTRAINT fk_price_history_asset FOREIGN KEY (asset_id) REFERENCES Assets (asset_id)
);
CREATE TABLE Order_Book_Snapshots (
    snapshot_id      INT        NOT NULL IDENTITY(1,1),
    asset_id         INT        NOT NULL,
    total_bid_volume BIGINT     NOT NULL DEFAULT 0,
    total_ask_volume BIGINT     NOT NULL DEFAULT 0,
    recorded_at      DATETIME   NOT NULL DEFAULT GETDATE(),

    CONSTRAINT pk_snapshots       PRIMARY KEY (snapshot_id),
    CONSTRAINT fk_snapshots_asset FOREIGN KEY (asset_id) REFERENCES Assets (asset_id)
);
CREATE INDEX idx_orders_matching      ON Orders            (asset_id, status, order_type, price, created_at);
CREATE INDEX idx_price_history_charts ON Price_History     (asset_id, time_interval);
CREATE INDEX idx_portfolio_user       ON Portfolio_Holdings (user_id);
