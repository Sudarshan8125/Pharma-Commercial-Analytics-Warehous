USE pharma_analytics;

-- 1. Rank prescribers by prescription volume over the latest 13 weeks.
WITH recent_volume AS (
    SELECT
        npi,
        product_id,
        SUM(trx) AS total_trx,
        SUM(nrx) AS total_nrx
    FROM prescriptions
    WHERE week_ending >= (
        SELECT DATE_SUB(MAX(week_ending), INTERVAL 12 WEEK)
        FROM prescriptions
    )
    GROUP BY npi, product_id
)
SELECT
    npi,
    product_id,
    total_trx,
    total_nrx,
    NTILE(10) OVER (PARTITION BY product_id ORDER BY total_trx DESC) AS volume_decile
FROM recent_volume
ORDER BY product_id, total_trx DESC;


-- 2. Show weekly trend, prior-week activity, and a four-week moving average.
WITH weekly_trend AS (
    SELECT
        npi,
        product_id,
        week_ending,
        trx,
        LAG(trx) OVER (
            PARTITION BY npi, product_id
            ORDER BY week_ending
        ) AS prior_week_trx,
        AVG(trx) OVER (
            PARTITION BY npi, product_id
            ORDER BY week_ending
            ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
        ) AS moving_avg_4w
    FROM prescriptions
)
SELECT
    npi,
    product_id,
    week_ending,
    trx,
    prior_week_trx,
    trx - prior_week_trx AS week_over_week_change,
    ROUND(moving_avg_4w, 2) AS moving_avg_4w
FROM weekly_trend
ORDER BY npi, product_id, week_ending;


-- 3. Compare average weekly TRx in four-week windows before and after calls.
-- This is descriptive association, not a causal estimate.
WITH call_windows AS (
    SELECT
        c.call_id,
        c.npi,
        c.call_datetime,
        DATE(c.call_datetime) AS call_date
    FROM calls AS c
),
windowed_activity AS (
    SELECT
        cw.call_id,
        cw.npi,
        AVG(CASE
            WHEN p.week_ending BETWEEN DATE_SUB(cw.call_date, INTERVAL 28 DAY)
                                   AND cw.call_date
            THEN p.trx
        END) AS avg_trx_before,
        AVG(CASE
            WHEN p.week_ending > cw.call_date
             AND p.week_ending <= DATE_ADD(cw.call_date, INTERVAL 28 DAY)
            THEN p.trx
        END) AS avg_trx_after
    FROM call_windows AS cw
    LEFT JOIN prescriptions AS p
      ON p.npi = cw.npi
    GROUP BY cw.call_id, cw.npi
)
SELECT
    call_id,
    npi,
    ROUND(avg_trx_before, 2) AS avg_trx_before,
    ROUND(avg_trx_after, 2) AS avg_trx_after,
    ROUND(avg_trx_after - avg_trx_before, 2) AS observed_difference
FROM windowed_activity
ORDER BY observed_difference DESC;


-- 4. Rank representatives by total TRx within each region for 2025.
WITH rep_volume AS (
    SELECT
        r.rep_id,
        r.rep_name,
        rg.region_name,
        SUM(p.trx) AS total_trx
    FROM reps AS r
    JOIN regions AS rg
      ON rg.region_id = r.region_id
    JOIN territories AS t
      ON t.rep_id = r.rep_id
    JOIN prescribers AS pr
      ON pr.territory_id = t.territory_id
    JOIN prescriptions AS p
      ON p.npi = pr.npi
    WHERE p.week_ending >= '2025-01-01'
      AND p.week_ending < '2026-01-01'
    GROUP BY r.rep_id, r.rep_name, rg.region_name
)
SELECT
    rep_id,
    rep_name,
    region_name,
    total_trx,
    RANK() OVER (PARTITION BY region_name ORDER BY total_trx DESC) AS regional_rank
FROM rep_volume
ORDER BY region_name, regional_rank;


-- 5. Compare actual quarterly TRx with prescriber-product targets by territory.
WITH actuals AS (
    SELECT
        npi,
        product_id,
        DATE_ADD(
            MAKEDATE(YEAR(week_ending), 1),
            INTERVAL (QUARTER(week_ending) - 1) * 3 MONTH
        ) AS quarter_start,
        SUM(trx) AS actual_trx
    FROM prescriptions
    GROUP BY
        npi,
        product_id,
        DATE_ADD(
            MAKEDATE(YEAR(week_ending), 1),
            INTERVAL (QUARTER(week_ending) - 1) * 3 MONTH
        )
),
territory_totals AS (
    SELECT
        t.territory_id,
        t.territory_name,
        rg.region_name,
        a.quarter_start,
        SUM(a.actual_trx) AS actual_trx,
        SUM(qt.target_trx) AS target_trx
    FROM actuals AS a
    JOIN quarterly_targets AS qt
      ON qt.npi = a.npi
     AND qt.product_id = a.product_id
     AND qt.quarter_start = a.quarter_start
    JOIN prescribers AS pr
      ON pr.npi = a.npi
    JOIN territories AS t
      ON t.territory_id = pr.territory_id
    JOIN regions AS rg
      ON rg.region_id = t.region_id
    GROUP BY
        t.territory_id, t.territory_name, rg.region_name, a.quarter_start
)
SELECT
    territory_id,
    territory_name,
    region_name,
    quarter_start,
    actual_trx,
    target_trx,
    actual_trx - target_trx AS variance_trx,
    ROUND(100.0 * actual_trx / NULLIF(target_trx, 0), 2) AS attainment_pct
FROM territory_totals
ORDER BY quarter_start, attainment_pct;


-- 6. Classify each prescriber's first observed prescription week.
WITH first_activity AS (
    SELECT
        npi,
        MIN(week_ending) AS first_rx_week
    FROM prescriptions
    WHERE trx > 0
    GROUP BY npi
)
SELECT
    YEAR(p.week_ending) AS activity_year,
    QUARTER(p.week_ending) AS activity_quarter,
    COUNT(DISTINCT CASE
        WHEN fa.first_rx_week = p.week_ending THEN p.npi
    END) AS newly_active_prescribers,
    COUNT(DISTINCT p.npi) AS active_prescribers
FROM prescriptions AS p
JOIN first_activity AS fa
  ON fa.npi = p.npi
WHERE p.trx > 0
GROUP BY YEAR(p.week_ending), QUARTER(p.week_ending)
ORDER BY activity_year, activity_quarter;


-- 7. Product mix by territory and quarter.
WITH territory_product_volume AS (
    SELECT
        t.territory_id,
        t.territory_name,
        p.product_id,
        p.product_name,
        DATE_ADD(
            MAKEDATE(YEAR(rx.week_ending), 1),
            INTERVAL (QUARTER(rx.week_ending) - 1) * 3 MONTH
        ) AS quarter_start,
        SUM(rx.trx) AS total_trx
    FROM prescriptions AS rx
    JOIN prescribers AS pr
      ON pr.npi = rx.npi
    JOIN territories AS t
      ON t.territory_id = pr.territory_id
    JOIN products AS p
      ON p.product_id = rx.product_id
    GROUP BY
        t.territory_id,
        t.territory_name,
        p.product_id,
        p.product_name,
        DATE_ADD(
            MAKEDATE(YEAR(rx.week_ending), 1),
            INTERVAL (QUARTER(rx.week_ending) - 1) * 3 MONTH
        )
)
SELECT
    territory_id,
    territory_name,
    quarter_start,
    product_id,
    product_name,
    total_trx,
    ROUND(
        100.0 * total_trx
        / NULLIF(SUM(total_trx) OVER (
            PARTITION BY territory_id, quarter_start
        ), 0),
        2
    ) AS product_share_pct
FROM territory_product_volume
ORDER BY territory_id, quarter_start, product_share_pct DESC;
