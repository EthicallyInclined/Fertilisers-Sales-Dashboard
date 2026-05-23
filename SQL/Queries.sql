-- ============================================================
-- AGRIFLOW FERTILIZERS - DATA ENGINEERING & ANALYTICS PIPELINE
-- SQL Scripts | Version 1.0 | May 2026
-- ============================================================

-- ===========================================
-- SECTION 1: DATABASE & SCHEMA SETUP
-- ===========================================

CREATE DATABASE IF NOT EXISTS agriflow_db;
USE agriflow_db;

-- Raw staging table
CREATE TABLE IF NOT EXISTS stg_fertilizer_sales (
    TransactionID   VARCHAR(12) PRIMARY KEY,
    Date            DATE,
    Year            SMALLINT,
    Month           TINYINT,
    Quarter         CHAR(2),
    Season          VARCHAR(10),
    State           VARCHAR(50),
    District        VARCHAR(50),
    Product         VARCHAR(50),
    Category        VARCHAR(30),
    Quantity_MT     INT,
    Unit_Price      DECIMAL(10,2),
    Discount_Pct    DECIMAL(5,3),
    Revenue         DECIMAL(12,2),
    COGS            DECIMAL(12,2),
    Gross_Profit    DECIMAL(12,2),
    Channel         VARCHAR(40),
    SalesRep        VARCHAR(10),
    CustomerType    VARCHAR(30),
    ReturnFlag      VARCHAR(3),
    ingestion_ts    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Dimension: Products
CREATE TABLE IF NOT EXISTS dim_product (
    product_id      INT AUTO_INCREMENT PRIMARY KEY,
    product_name    VARCHAR(50) UNIQUE,
    category        VARCHAR(30),
    base_price      DECIMAL(10,2),
    base_cost       DECIMAL(10,2),
    margin_pct      DECIMAL(5,2) AS (ROUND((base_price - base_cost)/base_price*100,2)) STORED
);

-- Dimension: Geography
CREATE TABLE IF NOT EXISTS dim_geography (
    geo_id          INT AUTO_INCREMENT PRIMARY KEY,
    state           VARCHAR(50),
    district        VARCHAR(50),
    region          VARCHAR(20),
    UNIQUE KEY uq_geo (state, district)
);

-- Dimension: Date
CREATE TABLE IF NOT EXISTS dim_date (
    date_id         DATE PRIMARY KEY,
    year            SMALLINT,
    month           TINYINT,
    month_name      VARCHAR(12),
    quarter         CHAR(2),
    season          VARCHAR(10),
    is_peak_season  TINYINT(1)
);

-- Dimension: Sales Channel
CREATE TABLE IF NOT EXISTS dim_channel (
    channel_id   INT AUTO_INCREMENT PRIMARY KEY,
    channel_name VARCHAR(40) UNIQUE,
    channel_type VARCHAR(20)
);

-- Fact Table
CREATE TABLE IF NOT EXISTS fact_sales (
    fact_id         BIGINT AUTO_INCREMENT PRIMARY KEY,
    transaction_id  VARCHAR(12),
    date_id         DATE,
    product_id      INT,
    geo_id          INT,
    channel_id      INT,
    sales_rep       VARCHAR(10),
    customer_type   VARCHAR(30),
    quantity_mt     INT,
    unit_price      DECIMAL(10,2),
    discount_pct    DECIMAL(5,3),
    revenue         DECIMAL(12,2),
    cogs            DECIMAL(12,2),
    gross_profit    DECIMAL(12,2),
    return_flag     VARCHAR(3),
    FOREIGN KEY (date_id)    REFERENCES dim_date(date_id),
    FOREIGN KEY (product_id) REFERENCES dim_product(product_id),
    FOREIGN KEY (geo_id)     REFERENCES dim_geography(geo_id),
    FOREIGN KEY (channel_id) REFERENCES dim_channel(channel_id)
);

-- ===========================================
-- SECTION 2: DATA QUALITY CHECKS
-- ===========================================

-- Check 1: Null values in critical columns
SELECT 
    SUM(CASE WHEN TransactionID IS NULL THEN 1 ELSE 0 END) AS null_txn_id,
    SUM(CASE WHEN Date IS NULL THEN 1 ELSE 0 END)          AS null_date,
    SUM(CASE WHEN Revenue < 0 THEN 1 ELSE 0 END)           AS negative_revenue,
    SUM(CASE WHEN Quantity_MT <= 0 THEN 1 ELSE 0 END)      AS zero_qty,
    COUNT(*)                                                AS total_rows
FROM stg_fertilizer_sales;

-- Check 2: Duplicate transactions
SELECT TransactionID, COUNT(*) AS cnt
FROM stg_fertilizer_sales
GROUP BY TransactionID HAVING cnt > 1;

-- Check 3: Revenue sanity (Revenue ≈ Qty * Unit_Price * (1 - Discount))
SELECT COUNT(*) AS revenue_mismatches
FROM stg_fertilizer_sales
WHERE ABS(Revenue - (Quantity_MT * Unit_Price)) > 1;

-- ===========================================
-- SECTION 3: DIMENSION POPULATION (ETL)
-- ===========================================

INSERT IGNORE INTO dim_product (product_name, category, base_price, base_cost) VALUES
('Urea',             'Nitrogenous', 600.00, 280.00),
('DAP',              'Phosphatic',  1350.00, 900.00),
('MOP',              'Potassic',    900.00,  600.00),
('NPK 10-26-26',     'Complex',     1200.00, 820.00),
('SSP',              'Phosphatic',  420.00,  200.00),
('Ammonium Sulphate','Nitrogenous', 650.00,  350.00),
('Calcium Nitrate',  'Nitrogenous', 850.00,  500.00),
('Zinc Sulphate',    'Micronutrient',350.00, 180.00);

INSERT IGNORE INTO dim_channel (channel_name, channel_type) VALUES
('Dealer',             'Indirect'),
('Direct Farm',        'Direct'),
('Government Scheme',  'Government'),
('Cooperative Society','Indirect'),
('Online Portal',      'Digital');

INSERT IGNORE INTO dim_geography (state, district, region)
SELECT DISTINCT State, District,
    CASE 
        WHEN State IN ('Uttar Pradesh','Bihar','Madhya Pradesh') THEN 'Central'
        WHEN State IN ('Punjab','Haryana','Rajasthan')           THEN 'North'
        WHEN State IN ('Maharashtra','Gujarat')                  THEN 'West'
        WHEN State IN ('Andhra Pradesh','Karnataka')             THEN 'South'
        ELSE 'Other'
    END
FROM stg_fertilizer_sales;

-- ===========================================
-- SECTION 4: ANALYTICAL QUERIES
-- ===========================================

-- A) Annual Revenue & YoY Growth
WITH annual AS (
    SELECT Year, 
           ROUND(SUM(Revenue)/1e6,2)      AS revenue_mn,
           ROUND(SUM(Gross_Profit)/1e6,2) AS profit_mn,
           SUM(Quantity_MT)               AS volume_mt
    FROM stg_fertilizer_sales WHERE ReturnFlag='No'
    GROUP BY Year
)
SELECT Year, revenue_mn, profit_mn, volume_mt,
    ROUND((revenue_mn - LAG(revenue_mn) OVER(ORDER BY Year))
          / LAG(revenue_mn) OVER(ORDER BY Year) * 100, 1) AS yoy_growth_pct
FROM annual ORDER BY Year;

-- B) Top 5 Products by Revenue
SELECT Product, Category,
    ROUND(SUM(Revenue)/1e6,2) AS revenue_mn,
    SUM(Quantity_MT)          AS volume_mt,
    ROUND(AVG(Gross_Profit/Revenue)*100,1) AS avg_margin_pct
FROM stg_fertilizer_sales WHERE ReturnFlag='No'
GROUP BY Product, Category
ORDER BY revenue_mn DESC LIMIT 5;

-- C) State-wise Performance with Rank
SELECT State,
    ROUND(SUM(Revenue)/1e6,2)      AS revenue_mn,
    SUM(Quantity_MT)               AS volume_mt,
    ROUND(AVG(Discount_Pct)*100,1) AS avg_discount_pct,
    RANK() OVER(ORDER BY SUM(Revenue) DESC) AS revenue_rank
FROM stg_fertilizer_sales WHERE ReturnFlag='No'
GROUP BY State;

-- D) Seasonal Sales Pattern
SELECT Season, Quarter, Month,
    COUNT(*)                       AS transactions,
    ROUND(SUM(Revenue)/1e6,2)      AS revenue_mn,
    ROUND(SUM(Quantity_MT)/1000,1) AS volume_k_mt
FROM stg_fertilizer_sales WHERE ReturnFlag='No'
GROUP BY Season, Quarter, Month ORDER BY Month;

-- E) Channel Efficiency Analysis
SELECT Channel,
    COUNT(*)                               AS orders,
    ROUND(SUM(Revenue)/1e6,2)             AS revenue_mn,
    ROUND(AVG(Discount_Pct)*100,2)        AS avg_discount_pct,
    ROUND(SUM(Gross_Profit)/SUM(Revenue)*100,1) AS gross_margin_pct,
    SUM(CASE WHEN ReturnFlag='Yes' THEN 1 ELSE 0 END) AS returns
FROM stg_fertilizer_sales
GROUP BY Channel ORDER BY revenue_mn DESC;

-- F) SalesRep Leaderboard (Top 10)
SELECT SalesRep,
    COUNT(*)                       AS deals,
    ROUND(SUM(Revenue)/1e6,2)      AS revenue_mn,
    ROUND(AVG(Discount_Pct)*100,1) AS avg_discount_pct,
    SUM(CASE WHEN ReturnFlag='Yes' THEN 1 ELSE 0 END) AS returns,
    RANK() OVER(ORDER BY SUM(Revenue) DESC) AS rank_rev
FROM stg_fertilizer_sales WHERE ReturnFlag='No'
GROUP BY SalesRep ORDER BY rank_rev LIMIT 10;

-- G) Customer Segment Profitability
SELECT CustomerType,
    COUNT(*)                               AS transactions,
    ROUND(SUM(Revenue)/1e6,2)             AS revenue_mn,
    ROUND(SUM(Gross_Profit)/SUM(Revenue)*100,1) AS margin_pct,
    ROUND(SUM(Revenue)/COUNT(*),0)        AS avg_order_value
FROM stg_fertilizer_sales WHERE ReturnFlag='No'
GROUP BY CustomerType ORDER BY revenue_mn DESC;

-- H) Rolling 3-Month Revenue (Window Function)
SELECT Date, Revenue,
    ROUND(AVG(Revenue) OVER(
        ORDER BY Date ROWS BETWEEN 89 PRECEDING AND CURRENT ROW
    ),2) AS rolling_90d_avg
FROM stg_fertilizer_sales WHERE ReturnFlag='No'
ORDER BY Date;

-- I) Return Analysis by Product
SELECT Product, Category,
    COUNT(*)                                          AS total_sales,
    SUM(CASE WHEN ReturnFlag='Yes' THEN 1 ELSE 0 END) AS returns,
    ROUND(SUM(CASE WHEN ReturnFlag='Yes' THEN 1 ELSE 0 END)/COUNT(*)*100,1) AS return_rate_pct
FROM stg_fertilizer_sales
GROUP BY Product, Category ORDER BY return_rate_pct DESC;

-- J) Cohort: First Purchase Month Retention
WITH first_buy AS (
    SELECT District, MIN(DATE_FORMAT(Date,'%Y-%m')) AS cohort_month
    FROM stg_fertilizer_sales GROUP BY District
)
SELECT f.cohort_month, COUNT(DISTINCT s.District) AS active_districts
FROM first_buy f
JOIN stg_fertilizer_sales s ON s.District=f.District
GROUP BY f.cohort_month ORDER BY f.cohort_month;

-- ===========================================
-- SECTION 5: MATERIALIZED VIEWS / SUMMARY TABLES
-- ===========================================

CREATE OR REPLACE VIEW vw_monthly_summary AS
SELECT Year, Month, Quarter, Season,
    COUNT(*)                               AS transactions,
    ROUND(SUM(Revenue)/1e6,2)             AS revenue_mn,
    ROUND(SUM(COGS)/1e6,2)               AS cogs_mn,
    ROUND(SUM(Gross_Profit)/1e6,2)        AS profit_mn,
    ROUND(SUM(Gross_Profit)/SUM(Revenue)*100,1) AS margin_pct,
    SUM(Quantity_MT)                       AS volume_mt
FROM stg_fertilizer_sales WHERE ReturnFlag='No'
GROUP BY Year, Month, Quarter, Season;

CREATE OR REPLACE VIEW vw_product_scorecard AS
SELECT Product, Category,
    ROUND(SUM(Revenue)/1e6,2)             AS revenue_mn,
    SUM(Quantity_MT)                       AS volume_mt,
    ROUND(SUM(Gross_Profit)/SUM(Revenue)*100,1) AS margin_pct,
    ROUND(AVG(Discount_Pct)*100,1)        AS avg_discount_pct,
    SUM(CASE WHEN ReturnFlag='Yes' THEN 1 ELSE 0 END) AS returns
FROM stg_fertilizer_sales
GROUP BY Product, Category;
