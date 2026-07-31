-- R2-F-B deployed atomic writer manifest/idempotency hardening.
-- This independent deployment-history driver intentionally reuses only the
-- three corrected function definitions in the authoritative cutover source.
-- Transaction control is supplied by the rehearsal/formal deployment driver.
\set ON_ERROR_STOP on
\pset pager off
\set r2_f_b_hardening_only 1
\ir school_tuition_r2_f_b_atomic_generate_cutover.sql
