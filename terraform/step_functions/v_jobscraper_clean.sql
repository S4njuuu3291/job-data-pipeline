-- =========================================================
-- VIEW: v_jobscraper_clean
-- Deskripsi: Membersihkan & mengklasifikasikan job postings
--            Menentukan apakah job adalah 'NEW' atau 'EXISTING'
--            berdasarkan first_seen_at vs scraped_at
--            
-- Cara deploy: Jalankan di Athena Query Editor
-- =========================================================

CREATE OR REPLACE VIEW "v_jobscraper_clean" AS
WITH
  -- Step 1: Normalisasi URL (buang query params, hash, trailing slash)
  base_data AS (
    SELECT *,
      regexp_replace(lower(job_url), '(\\?.*|#.*|/$)', '') AS clean_url
    FROM "jobscraper_db"."jobscraper_silver_table"
  ),

  -- Step 2: Hitung first_seen_at & first_date per URL sepanjang sejarah
  stats_cte AS (
    SELECT *,
      MIN(scraped_at) OVER (PARTITION BY clean_url) AS first_seen_at,
      MIN(ingestion_date) OVER (PARTITION BY clean_url) AS first_ingestion_date,
      ROW_NUMBER() OVER (
        PARTITION BY clean_url, ingestion_date
        ORDER BY scraped_at DESC
      ) AS rn
    FROM base_data
  ),

  -- Step 3: Dedup per hari + klasifikasi NEW/EXISTING
  -- NEW = hari pertama URL ini muncul (berdasarkan ingestion_date)
  -- EXISTING = URL sudah pernah muncul di hari sebelumnya
  cleaning AS (
    SELECT *,
      CASE
        WHEN (ingestion_date = first_ingestion_date) THEN 'NEW'
        ELSE 'EXISTING'
      END AS discovery_type
    FROM stats_cte
    WHERE rn = 1
  )

-- Step 4: Output final with keyword column
SELECT
  job_id,
  job_title,
  company_name,
  location,
  job_url,
  keyword,
  ingestion_date,
  scraped_at,
  first_seen_at,
  first_ingestion_date,
  discovery_type,
  platform
FROM cleaning;
