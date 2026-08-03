-- P0-B2 reuses the already-reviewed School-only P0-B1 synthetic fixture.
-- Required p0b2_fixture_action: preflight | insert | cleanup | residue.
-- The included lifecycle owns only fixed b1b10000-* UUIDs and verifies marker
-- ownership before exact cleanup. It never references Cash DB objects.
\set ON_ERROR_STOP on
\if :{?p0b2_fixture_action}
\else
  \echo 'P0B2_FIXTURE_ACTION_REQUIRED'
  \quit
\endif
\set p0b1_fixture_action :p0b2_fixture_action
\ir school_tuition_p0b1_concurrency_fixture_lifecycle_20260803.sql
