-- Tester la progression de CREATE INDEX dans pg_stat_progress_create_index
-- Usage: ouvrir 2 terminaux
--   Terminal 1: psql -h localhost -U postgres -d test -f test-progress.sql
--   Terminal 2: psql -h localhost -U postgres -d test  (puis \watch 1 sur la requête de monitoring)

-- ── Préparation ─────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS t;
CREATE TABLE t (id serial, v vector(128));

INSERT INTO t (v)
SELECT array_fill(random()::float4, ARRAY[128])::vector
FROM generate_series(1, 300000);

ANALYZE t;

-- ── Monitoring (à lancer dans le terminal 2 AVANT le CREATE INDEX) ──────────
-- \watch 1
SELECT
    pid,
    phase,
    tuples_done,
    tuples_total,
    CASE WHEN tuples_total > 0
         THEN round(100.0 * tuples_done / tuples_total, 1)::text || '%'
         ELSE '?'
    END AS progression
FROM pg_stat_progress_create_index;

-- ── Test série (Plain storage) ───────────────────────────────────────────────
-- À lancer dans terminal 1, surveiller dans terminal 2
CREATE INDEX idx_plain ON t USING diskann (v);
DROP INDEX idx_plain;

-- ── Test série (SBQ — passe par la phase "training quantizer") ───────────────
CREATE INDEX idx_sbq ON t USING diskann (v) WITH (storage_layout = memory_optimized);
DROP INDEX idx_sbq;

-- ── Test parallèle (SBQ) ─────────────────────────────────────────────────────
-- En parallèle: plusieurs lignes dans pg_stat_progress_create_index (une par worker)
SET max_parallel_maintenance_workers = 4;
SET maintenance_work_mem = '256MB';
CREATE INDEX idx_parallel ON t USING diskann (v) WITH (storage_layout = memory_optimized);
DROP INDEX idx_parallel;

RESET max_parallel_maintenance_workers;
RESET maintenance_work_mem;
