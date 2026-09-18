-- 0004_pg_stat_statements.sql
-- pg_stat_statements is what turns "the app feels slow" into "this query ran
-- 40,000 times and nobody indexed it". The RDS parameter group already preloads
-- the library (infra/modules/rds/main.tf); this makes the local database match,
-- so a query plan investigated locally behaves the way it will in RDS.
--
-- The extension needs the library in shared_preload_libraries to actually
-- collect anything -- see the `command:` override in docker-compose.yml.

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
