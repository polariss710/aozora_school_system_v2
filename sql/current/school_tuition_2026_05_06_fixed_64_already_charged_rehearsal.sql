-- ROLLBACK rehearsal wrapper. The migration core is byte-identical to formal deployment.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL REPEATABLE READ;
\ir school_tuition_2026_05_06_fixed_64_already_charged_core.sql
ROLLBACK;
