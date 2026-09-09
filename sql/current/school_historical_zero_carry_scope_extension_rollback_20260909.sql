-- =============================================================================
-- 历史零结转：范围闸门扩围 —— 回滚
--
-- 把入口函数逐字节还原为部署前的生产 canonical 定义，并还原 COMMENT。
--
-- ⛔ 硬停止：若 b17abc58 / 2026-08 的 evidence 【已经建立】，本脚本拒绝执行。
--    收窄闸门不会删除已建立的 evidence，也不会让 resolver 退回 incomplete；
--    那时的「回滚」只还原了入口的准入范围，【不还原业务事实】，
--    把两者混为一谈会给出错误的安全感。
--    确需在 evidence 已存在时收窄范围，请显式 -v allow_evidence_exists=yes，
--    并在事后【不得】把整体状态描述为「恢复到部署前」。
--
-- 用法
--   psql -v ON_ERROR_STOP=1 -f <本文件>
--   psql -v ON_ERROR_STOP=1 -v allow_evidence_exists=yes -f <本文件>
-- =============================================================================
\set ON_ERROR_STOP on

\if :{?allow_evidence_exists}
\else
  \set allow_evidence_exists 'no'
\endif

BEGIN;

SELECT set_config('hzc.allow_evidence_exists', :'allow_evidence_exists', false);

DO $pre$
DECLARE v_oid oid; v_md5 text; v_n int; v_acl text;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_local_create_student_monthly_settlement_historical_compl';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'HZCR_OVERLOAD: public.% 有 % 个重载（应为 1）', 'school_local_create_student_monthly_settlement_historical_compl', v_n; END IF;

  v_oid := to_regprocedure('public.school_local_create_student_monthly_settlement_historical_compl(uuid,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text)');
  IF v_oid IS NULL THEN RAISE EXCEPTION 'HZCR_MISSING'; END IF;
  SELECT md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,'')
    INTO v_md5, v_acl FROM pg_proc p WHERE p.oid=v_oid;

  -- 只回滚「本次部署的结果」。已经是部署前状态就没什么可回滚的，
  -- 是别的东西就更不该在这里覆盖。
  IF v_md5 = '3036165ab9352e7701b43f40c19018fc' THEN
    RAISE EXCEPTION 'HZCR_ALREADY_BASELINE: 当前已是部署前定义，无需回滚'; END IF;
  IF v_md5 <> '1e071b2b9caa465e10f8879a2e11926a' THEN
    RAISE EXCEPTION 'HZCR_UNEXPECTED_DEFINITION: 得 %  —— 不是本次部署的结果，拒绝覆盖', v_md5; END IF;
  IF v_acl <> '{postgres=X/postgres,service_role=X/postgres}' THEN
    RAISE EXCEPTION 'HZCR_ACL_DRIFT: 得 %', v_acl; END IF;

  -- 锁住 evidence 表再数，避免「数完到回滚之间又插进来一行」。
  LOCK TABLE public.school_student_monthly_settlement_historical_completion_evidence
    IN ACCESS EXCLUSIVE MODE;
  SELECT count(*) INTO v_n
    FROM public.school_student_monthly_settlement_historical_completion_evidence
   WHERE student_id='b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid
     AND settlement_month='2026-08';
  IF v_n > 0 AND current_setting('hzc.allow_evidence_exists') <> 'yes' THEN
    RAISE EXCEPTION 'HZCR_EVIDENCE_EXISTS: 已建立 % 行 evidence。收窄闸门【不会】删除它，'
      '也【不会】让 resolver 退回 incomplete。确需继续请显式 -v allow_evidence_exists=yes', v_n;
  END IF;
END
$pre$;

CREATE OR REPLACE FUNCTION public.school_local_create_student_monthly_settlement_historical_compl(p_student_id uuid, p_settlement_month text, p_business_entity_id uuid, p_expected_lesson_manifest_sha256 text, p_expected_makeup_manifest_sha256 text, p_expected_active_revision_id uuid, p_expected_tuition_bill_id uuid, p_expected_income_record_id uuid, p_expected_cash_linkage_event_id uuid, p_expected_cash_request_id uuid, p_expected_cash_transaction_id uuid, p_created_by_actor_id uuid, p_reason text, p_confirmation_text text, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'HISTORICAL_ZERO_CARRY_LOCAL_TRUSTED_ROLE_REQUIRED';
  end if;
  if not (
    p_settlement_month = '2026-07'
    and p_business_entity_id = '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid
    and p_student_id in (
      'eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,
      '881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,
      'a7b163a0-201e-4867-9b94-372343356a80'::uuid,
      '4c6f1473-7d44-467d-a70b-30f02e7cf8cd'::uuid
    )
  ) and not exists (
    select 1 from public.school_students s
    where s.id = p_student_id
      and s.business_entity_id = p_business_entity_id
      and (s.name ilike '%codex-test%' or coalesce(s.note, '') ilike '%codex-test%')
  ) then
    raise exception 'HISTORICAL_ZERO_CARRY_LOCAL_SCOPE_NOT_APPROVED';
  end if;

  return public.school_create_student_monthly_settlement_historical_completion_evidence_core(
    p_student_id, p_settlement_month, p_business_entity_id,
    p_expected_lesson_manifest_sha256, p_expected_makeup_manifest_sha256,
    p_expected_active_revision_id, p_expected_tuition_bill_id,
    p_expected_income_record_id, p_expected_cash_linkage_event_id,
    p_expected_cash_request_id, p_expected_cash_transaction_id,
    p_created_by_actor_id, p_reason, p_confirmation_text, p_idempotency_key
  );
end
$function$;

COMMENT ON FUNCTION public.school_local_create_student_monthly_settlement_historical_compl(uuid,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text) IS 'Service-role-only local trusted wrapper for the four approved 2026-07 scopes; no browser entry point.';

DO $post$
DECLARE v_oid oid; v_md5 text; v_acl text; v_cmt text; v_cfg text;
BEGIN
  v_oid := to_regprocedure('public.school_local_create_student_monthly_settlement_historical_compl(uuid,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text)');
  SELECT md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,''),
         obj_description(p.oid,'pg_proc'), coalesce(array_to_string(p.proconfig,','),'')
    INTO v_md5, v_acl, v_cmt, v_cfg FROM pg_proc p WHERE p.oid=v_oid;
  IF v_md5 <> '3036165ab9352e7701b43f40c19018fc' THEN
    RAISE EXCEPTION 'HZCR_POST_MD5: 得 %  期望 %', v_md5, '3036165ab9352e7701b43f40c19018fc'; END IF;
  IF v_acl <> '{postgres=X/postgres,service_role=X/postgres}' THEN RAISE EXCEPTION 'HZCR_POST_ACL: 得 %', v_acl; END IF;
  IF v_cfg <> 'search_path=pg_catalog, public' THEN
    RAISE EXCEPTION 'HZCR_POST_PROCONFIG: 得 %', v_cfg; END IF;
  IF v_cmt IS DISTINCT FROM 'Service-role-only local trusted wrapper for the four approved 2026-07 scopes; no browser entry point.' THEN
    RAISE EXCEPTION 'HZCR_POST_COMMENT: 得 %', coalesce(v_cmt,'<null>'); END IF;
  RAISE NOTICE 'HZC: 已逐字节还原为部署前定义';
END
$post$;

COMMIT;
