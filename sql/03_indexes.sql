USE pharma_analytics;

-- Indexes are declared alongside their tables in 01_schema.sql so that
-- schema setup is self-contained. This script inspects those indexes and
-- demonstrates how to review the optimizer's access path.
--
-- No extra indexes are added here: avoid creating duplicate indexes that
-- increase storage and write cost without adding a new access path.

SHOW INDEX FROM prescriptions;
SHOW INDEX FROM calls;
SHOW INDEX FROM quarterly_targets;
SHOW INDEX FROM prescribers;

-- Review the optimizer's estimated plan for a common product/time filter.
-- Use EXPLAIN ANALYZE on MySQL 8.0.18+ when you want actual execution metrics.
EXPLAIN FORMAT=TREE
SELECT npi, SUM(trx) AS total_trx
FROM prescriptions
WHERE product_id = 1
  AND week_ending >= '2025-10-01'
GROUP BY npi;

-- Review index cardinality estimates on the local MySQL instance.
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
