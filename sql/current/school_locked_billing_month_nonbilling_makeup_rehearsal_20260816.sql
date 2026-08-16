-- Complete migration + synthetic matrix + exact real-target correction in one
-- outer transaction. The final ROLLBACK is mandatory.
\set ON_ERROR_STOP on
\pset pager off
begin;
set local lock_timeout='10s';
set local statement_timeout='600s';
\set sun_chenfeng_caller_transaction 1
\ir school_locked_billing_month_nonbilling_makeup_sun_chenfeng_correction_20260816.sql
\ir ../tests/school_locked_billing_month_nonbilling_makeup_rollback_test_body_20260816.sql

-- The exact correction entry point is owner-only. JWT claims still identify the
-- approved active admin actor used by canonical membership/audit checks.
select set_config('request.jwt.claims',
  '{"sub":"25331ae9-3412-48b9-bdc3-e516caeaeba4","role":"authenticated"}',true);
select * from public.school_correct_sun_chenfeng_20260811_makeup_v1(
  '2026-08-01 14:02:23.647108+00'::timestamptz,
  '2026-07-31 15:51:01.478823+00'::timestamptz,
  '孙陈锋2026-08-01实际缺课；纠正错误ordinary actual并转待补，2026-08-11由田宇辰完成非计费补课；actor_user_id=25331ae9-3412-48b9-bdc3-e516caeaeba4',
  'CORRECT_SUN_CHENFENG_20260811_MAKEUP'
);

select 'SUN_CHENFENG_EXACT_CORRECTION_REHEARSAL_PASS' result;
rollback;
select 'SUN_CHENFENG_COMPLETE_REHEARSAL_ROLLED_BACK' result;
