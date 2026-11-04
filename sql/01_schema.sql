CREATE DATABASE IF NOT EXISTS pharma_analytics
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

USE pharma_analytics;

CREATE TABLE IF NOT EXISTS regions (
    region_id SMALLINT UNSIGNED NOT NULL,
    region_name VARCHAR(40) NOT NULL,
    PRIMARY KEY (region_id),
    UNIQUE KEY uq_regions_name (region_name)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS reps (
    rep_id SMALLINT UNSIGNED NOT NULL,
    rep_name VARCHAR(80) NOT NULL,
    region_id SMALLINT UNSIGNED NOT NULL,
    hire_date DATE NOT NULL,
    PRIMARY KEY (rep_id),
    KEY idx_reps_region (region_id),
    CONSTRAINT fk_reps_region
      FOREIGN KEY (region_id) REFERENCES regions (region_id)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS territories (
    territory_id SMALLINT UNSIGNED NOT NULL,
    territory_name VARCHAR(80) NOT NULL,
    region_id SMALLINT UNSIGNED NOT NULL,
    rep_id SMALLINT UNSIGNED NOT NULL,
    PRIMARY KEY (territory_id),
    KEY idx_territories_region (region_id),
    KEY idx_territories_rep (rep_id),
    CONSTRAINT fk_territories_region
      FOREIGN KEY (region_id) REFERENCES regions (region_id),
    CONSTRAINT fk_territories_rep
      FOREIGN KEY (rep_id) REFERENCES reps (rep_id)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS products (
    product_id TINYINT UNSIGNED NOT NULL,
    product_name VARCHAR(80) NOT NULL,
    molecule VARCHAR(80) NOT NULL,
    launch_date DATE NOT NULL,
    PRIMARY KEY (product_id),
    UNIQUE KEY uq_products_name (product_name)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS prescribers (
    npi CHAR(10) NOT NULL,
    specialty VARCHAR(60) NOT NULL,
    territory_id SMALLINT UNSIGNED NOT NULL,
    first_seen_date DATE NOT NULL,
    PRIMARY KEY (npi),
    KEY idx_prescribers_territory (territory_id),
    CONSTRAINT fk_prescribers_territory
      FOREIGN KEY (territory_id) REFERENCES territories (territory_id)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS prescriptions (
    npi CHAR(10) NOT NULL,
    product_id TINYINT UNSIGNED NOT NULL,
    week_ending DATE NOT NULL,
    trx INT UNSIGNED NOT NULL,
    nrx INT UNSIGNED NOT NULL,
    PRIMARY KEY (npi, product_id, week_ending),
    KEY idx_prescriptions_product_week (product_id, week_ending),
    KEY idx_prescriptions_week (week_ending),
    CONSTRAINT fk_prescriptions_prescriber
      FOREIGN KEY (npi) REFERENCES prescribers (npi),
    CONSTRAINT fk_prescriptions_product
      FOREIGN KEY (product_id) REFERENCES products (product_id),
    CONSTRAINT chk_prescriptions_nrx_trx
      CHECK (nrx <= trx)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS calls (
    call_id INT UNSIGNED NOT NULL,
    npi CHAR(10) NOT NULL,
    rep_id SMALLINT UNSIGNED NOT NULL,
    call_datetime DATETIME NOT NULL,
    channel VARCHAR(20) NOT NULL,
    outcome VARCHAR(40) NOT NULL,
    PRIMARY KEY (call_id),
    KEY idx_calls_npi_datetime (npi, call_datetime),
    KEY idx_calls_rep_datetime (rep_id, call_datetime),
    CONSTRAINT fk_calls_prescriber
      FOREIGN KEY (npi) REFERENCES prescribers (npi),
    CONSTRAINT fk_calls_rep
      FOREIGN KEY (rep_id) REFERENCES reps (rep_id)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS quarterly_targets (
    npi CHAR(10) NOT NULL,
    product_id TINYINT UNSIGNED NOT NULL,
    quarter_start DATE NOT NULL,
    target_trx INT UNSIGNED NOT NULL,
    target_nrx INT UNSIGNED NOT NULL,
    PRIMARY KEY (npi, product_id, quarter_start),
    KEY idx_targets_quarter_product (quarter_start, product_id),
    CONSTRAINT fk_targets_prescriber
      FOREIGN KEY (npi) REFERENCES prescribers (npi),
    CONSTRAINT fk_targets_product
      FOREIGN KEY (product_id) REFERENCES products (product_id),
    CONSTRAINT chk_targets_nrx_trx
      CHECK (target_nrx <= target_trx)
) ENGINE = InnoDB;
