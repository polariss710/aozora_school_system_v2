-- Phase BE-UI rollback test: apply the exact core inside one transaction, smoke test, then roll back.
\set ON_ERROR_STOP on
\pset pager off

begin;
\ir school_business_entity_ui_closure_core_20260806.sql

do $test$
declare
  v_actor uuid;
  v_result jsonb;
begin
  select membership.user_id into v_actor
  from public.school_app_memberships membership
  where membership.is_active
    and membership.role in ('admin','operator','read_only')
  order by case membership.role when 'admin' then 1 when 'operator' then 2 else 3 end,membership.user_id
  limit 1;

  if v_actor is null then
    raise exception 'BE_UI_TEST_ACTIVE_MEMBERSHIP_MISSING';
  end if;

  perform set_config('request.jwt.claim.sub',v_actor::text,true);
  v_result := public.school_get_profit_summary_schoolwide_v1('2026-01','2026-12');

  if jsonb_array_length(v_result->'summary_rows')<>2
     or jsonb_array_length(v_result->'audit_rows')<>7
     or not (v_result->'summary_rows' @> '[{"currency":"JPY"},{"currency":"CNY"}]'::jsonb) then
    raise exception 'BE_UI_PROFIT_READER_SMOKE_FAILED';
  end if;

  begin
    perform public.school_get_profit_summary_schoolwide_v1('2026-13','2026-01');
    raise exception 'BE_UI_INVALID_MONTH_WAS_ACCEPTED';
  exception when sqlstate '22023' then
    null;
  end;
end;
$test$;

select 'BE_UI_ROLLBACK_TEST_PASS' result;
rollback;
