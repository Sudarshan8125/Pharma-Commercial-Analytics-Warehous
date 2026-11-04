USE pharma_analytics;

-- The schema creates indexes needed for primary and foreign-key access.
-- These additional indexes target common filter and grouping patterns.
-- Run this file once after loading the tables.

CREATE INDEX idx_rx_product_week
    ON prescriptions (product_id, week_ending);

CREATE INDEX idx_calls_npi_time
    ON calls (npi, call_datetime);

CREATE INDEX idx_calls_rep_time
    ON calls (rep_id, call_datetime);

CREATE INDEX idx_targets_quarter_product
    ON quarterly_targets (quarter_start, product_id);

-- Inspect an analytical access path before drawing performance conclusions.
EXPLAIN ANALYZE
SELECT npi, SUM(trx) AS total_trx
FROM prescriptions
WHERE product_id = 1
  AND week_ending >= '2025-10-01'
GROUP BY npi;

-- Review index sizes and cardinality on the local MySQL instance.
SELECT
    TABLE_NAME,
    INDEX_NAME,
    GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS indexed_columns,
    MAX(CARDINALITY) AS estimated_cardinality
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = 'pharma_analytics'
GROUP BY TABLE_NAME, INDEX_NAME
ORDER BY TABLE_NAME, INDEX_NAME;

-- No benchmark figures are embedded here. Record measurements only after
-- running repeatable tests on the target MySQL version and hardware.
