-- Cash DB read-only invariants for School student monthly status Phase A.
\set ON_ERROR_STOP on
\pset pager off

do $cash_invariants$
begin
  if (select count(*) from public.home_external_transaction_requests)<>42
     or (select md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.home_external_transaction_requests t)<>'dfb00aaa210894f78c47285e21d2f222'
     or (select count(*) from public.home_cny_transactions)<>73
     or (select md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.home_cny_transactions t)<>'937cbd8d10480c5c5dabaab658eb2558'
     or (select count(*) from public.home_jpy_transactions)<>31
     or (select md5(coalesce(string_agg(to_jsonb(t)::text,'|' order by t.id),'')) from public.home_jpy_transactions t)<>'3f3f257b14b43c12925a8eecb7a8ca02' then
    raise exception 'STUDENT_STATUS_PHASE_A_CASH_INVARIANT_CHANGED';
  end if;
end;
$cash_invariants$;

select 'STUDENT_STATUS_PHASE_A_CASH_READ_ONLY_PASS' result;
