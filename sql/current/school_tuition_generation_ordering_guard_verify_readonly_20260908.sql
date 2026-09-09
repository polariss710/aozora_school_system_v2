-- =============================================================================
-- 学费生成顺序守卫：部署后只读验收
--
-- 设计   ~/aozora-security-20260827/school-generation-ordering-guard-design-20260908-v14.md
-- 部署   sql/current/school_tuition_generation_ordering_guard_deploy_20260908.sql
--
-- 【纯只读】。不写业务数据、不调 writer、不改任何定义。
-- 唯一的写入是 TEMP 表，不触及任何业务表。
--
-- 用法：
--   psql -v ON_ERROR_STOP=1 -f <本文件>
--
-- 任一断言失败即 RAISE EXCEPTION；全部通过时在末尾打印覆盖率报告。
-- ⚠️ 报告里出现 VR_COVERAGE_* 警告的项目，表示【该项未被本脚本验收】，
--    不是「通过」。
-- =============================================================================
\set ON_ERROR_STOP on
\echo '=== 顺序守卫：部署后只读验收 ==='

-- 临时表须在 READ ONLY 事务【之外】创建：READ ONLY 禁止 CREATE TABLE，
-- 但【允许】向临时表 INSERT。这样既能留住 READ ONLY 这个机器强制的保证，
-- 又能落扫描结果。
-- 【必须限定 pg_temp】：未限定的 DROP 会命中搜索路径上的同名【永久】表，
-- 而它在 BEGIN 之前执行、自动提交，READ ONLY 与末尾 ROLLBACK 都保护不了。
-- 新连接上尚无临时 schema 时，本语句只打一条 notice 并跳过。
DROP TABLE IF EXISTS pg_temp.vr_scan;
CREATE TEMP TABLE vr_scan(
  student_id uuid, billing_month text, ok boolean, sqlstate text, errcode text,
  eff_status text, eff_complete boolean, reader_complete boolean, has_keys boolean
);

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '600s';

-- -----------------------------------------------------------------------------
-- §1 五个函数的部署后状态
-- -----------------------------------------------------------------------------
DO $vr$
DECLARE
  r record; v_oid oid; v_md5 text; v_acl text; v_cfg text; v_cmt text; v_own text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('B','public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)',
     'c456d247f804058e8ae29ef4ba419599','{postgres=X/postgres,service_role=X/postgres}',
     'Phase B3: existing tuition facts are governed by lesson, settlement, bill, income, immutable and Gate contracts; frozen legacy student status is not an eligibility authority.'),
    ('G','public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text,text)',
     '40ef9ec344623bb7c02bf8aea670ad52',
     '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}',
     'R2-F-B authoritative atomic tuition writer. The public wrapper is R0-gated; clients submit no amounts or candidate details.'),
    ('C','public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text,text)',
     'dad1d0512d44114aed0d9c2a3b61480e','{postgres=X/postgres}',
     'R2-F-C owner-only atomic tuition core. New generation holds fixed-order SHARE table locks on lesson and settlement evidence tables until transaction end; public wrapper remains R0 blocked.'),
    ('F','public.school_generate_student_tuition_bill_atomic_base_core_v1(uuid,text,numeric,text,text,text,text)',
     '8b9b4fd5079a2794aa15c223bbbf9ffc','{postgres=X/postgres}',NULL),
    ('N','public.school_generate_student_tuition_next_revision_core(uuid,uuid,uuid,text,numeric,text,text,text,text)',
     '06262763ce6c223e1b271e2be005fdbb','{postgres=X/postgres}',NULL)
  ) AS t(code,sig,md5,acl,cmt) LOOP
    v_oid := to_regprocedure(r.sig);
    IF v_oid IS NULL THEN RAISE EXCEPTION 'VR_MISSING: % (%)', r.code, r.sig; END IF;
    SELECT md5(pg_get_functiondef(v_oid)), coalesce(proacl::text,''),
           coalesce(array_to_string(proconfig,','),''), obj_description(v_oid,'pg_proc'),
           pg_get_userbyid(proowner)
      INTO v_md5, v_acl, v_cfg, v_cmt, v_own FROM pg_proc WHERE oid = v_oid;
    -- owner 不在定义 md5 里。实测改 owner 会先触发上面的 ACL 断言（授予者随之改变），
    -- 故这条是【诊断】用：直接点名 owner，省去从 ACL 串里解码。
    IF v_own <> 'postgres' THEN
      RAISE EXCEPTION 'VR_OWNER: % 的 owner 为 %（应为 postgres）', r.code, v_own; END IF;
    IF v_md5 <> r.md5 THEN RAISE EXCEPTION 'VR_MD5: % 得 % 期望 %', r.code, v_md5, r.md5; END IF;
    -- C/F/N 若含 service_role 即为【权限扩大】：DROP 后重建时 public schema 的
    -- 默认授权会把它带回来，必须已被显式 REVOKE 掉。
    IF v_acl <> r.acl THEN
      -- 与 deploy 同一口径：集合不同和仅顺序不同是两回事，报文要分开。
      -- 顺序那一类的成因是 DROP 后默认授权把 service_role 先放回数组。
      IF EXISTS (SELECT unnest(string_to_array(btrim(v_acl,'{}'),','))
                 EXCEPT SELECT unnest(string_to_array(btrim(r.acl,'{}'),',')))
         OR EXISTS (SELECT unnest(string_to_array(btrim(r.acl,'{}'),','))
                    EXCEPT SELECT unnest(string_to_array(btrim(v_acl,'{}'),','))) THEN
        RAISE EXCEPTION 'VR_ACL_SET: % 权限集合与基线不同  实际 %  期望 %', r.code, v_acl, r.acl;
      ELSE
        RAISE EXCEPTION 'VR_ACL_ORDER: % 集合相同但数组顺序不同  实际 %  期望 %', r.code, v_acl, r.acl;
      END IF;
    END IF;
    IF v_cfg <> 'search_path=pg_catalog, public' THEN
      RAISE EXCEPTION 'VR_PROCONFIG: % 得 %', r.code, v_cfg; END IF;
    IF v_cmt IS DISTINCT FROM r.cmt THEN
      RAISE EXCEPTION 'VR_COMMENT: % 注释与基线不符', r.code; END IF;
  END LOOP;

  -- 旧签名必须已消失。这是【必要断言之一】，不是唯一防线：
  -- 它证明不了 PostgREST 的重载解析，那需要 HTTP 层证据。
  FOR r IN SELECT * FROM (VALUES
    ('public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text)'),
    ('public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'),
    ('public.school_generate_student_tuition_bill_atomic_base_core_v1(uuid,text,numeric,text,text,text)'),
    ('public.school_generate_student_tuition_next_revision_core(uuid,uuid,uuid,text,numeric,text,text,text)')
  ) AS t(sig) LOOP
    IF to_regprocedure(r.sig) IS NOT NULL THEN
      RAISE EXCEPTION 'VR_OLD_SIGNATURE_ALIVE: %  ← 重载歧义风险', r.sig;
    END IF;
  END LOOP;

  -- 对外返回签名【逐字节】。只数列数不够：同列数、不同名称或类型也会过。
  FOR r IN SELECT * FROM (VALUES
    ('public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text,text)',
     'TABLE(tuition_bill_id uuid, billing_identity_id uuid, income_record_id uuid, student_id uuid, business_entity_id uuid, billing_month text, generation_manifest_sha256 text, candidate_count integer, total_lesson_count integer, total_duration_hours numeric, total_base_lesson_fee_jpy numeric, total_aircon_fee_jpy numeric, total_fee_jpy numeric, billing_exchange_rate numeric, previous_carryover_cny numeric, billing_amount_cny numeric, bill_status text, income_status text, idempotent boolean, message text)'),
    ('public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text,text)',
     'TABLE(tuition_bill_id uuid, billing_identity_id uuid, income_record_id uuid, student_id uuid, business_entity_id uuid, billing_month text, generation_manifest_sha256 text, candidate_count integer, total_lesson_count integer, total_duration_hours numeric, total_base_lesson_fee_jpy numeric, total_aircon_fee_jpy numeric, total_fee_jpy numeric, billing_exchange_rate numeric, previous_carryover_cny numeric, billing_amount_cny numeric, bill_status text, income_status text, idempotent boolean, message text)')
  ) AS t(sig,expected) LOOP
    IF pg_get_function_result(to_regprocedure(r.sig)) IS DISTINCT FROM r.expected THEN
      RAISE EXCEPTION 'VR_RESULT_SHAPE: %  实际 %', r.sig,
        pg_get_function_result(to_regprocedure(r.sig));
    END IF;
  END LOOP;

  RAISE NOTICE 'VR §1: 五个函数定义 / ACL / proconfig / COMMENT / 旧签名 / 对外契约 —— 通过';
END $vr$;

-- -----------------------------------------------------------------------------
-- §2 BG（baseline core）仍不可达
--     它直接调 builder 并写账单，靠的是「仅 postgres 可执行、无生产调用方」。
--     只把这句写进文档会过期；写成断言才不会。
-- -----------------------------------------------------------------------------
DO $vr$
DECLARE v_oid oid; v_md5 text; v_acl text;
BEGIN
  v_oid := to_regprocedure('public.school_p0c_baseline_generate_atomic_core(uuid,text,numeric,text,text,text)');
  IF v_oid IS NULL THEN RAISE EXCEPTION 'VR_BG_MISSING'; END IF;
  SELECT md5(pg_get_functiondef(v_oid)), coalesce(proacl::text,'')
    INTO v_md5, v_acl FROM pg_proc WHERE oid = v_oid;
  IF v_md5 <> '5adc2283993493e1a6095b5fabe460b0' THEN
    RAISE EXCEPTION 'VR_BG_DRIFT: md5=%', v_md5; END IF;
  IF v_acl <> '{postgres=X/postgres}' THEN
    RAISE EXCEPTION 'VR_BG_ACL_WIDENED: %  ← 已被授权，重新评估可达性', v_acl; END IF;
  RAISE NOTICE 'VR §2: BG 仍为 postgres-only —— 通过';
END $vr$;

-- -----------------------------------------------------------------------------
-- §3 新对象结构
-- -----------------------------------------------------------------------------
DO $vr$
DECLARE v_n int; v_txt text;
BEGIN
  IF to_regclass('public.school_student_tuition_generation_ordering_ack_events') IS NULL THEN
    RAISE EXCEPTION 'VR_ACK_TABLE_MISSING'; END IF;

  -- 只核名称与类型不够：同名而约束列、CHECK 表达式、FK 目标或删除行为不同，
  -- 仍会通过。逐条核对【实际定义】+ 已验证 / 可延迟 / 默认延迟状态。
  SELECT string_agg(conname||' | '||pg_get_constraintdef(oid)||' | '
                    ||convalidated::text||condeferrable::text||condeferred::text,
                    E'\n' ORDER BY conname) INTO v_txt
    FROM pg_constraint WHERE conrelid='public.school_student_tuition_generation_ordering_ack_events'::regclass;
  IF v_txt IS DISTINCT FROM
'tuition_ordering_ack_bill_fkey | FOREIGN KEY (tuition_bill_id) REFERENCES school_student_tuition_bills(id) ON DELETE RESTRICT | truefalsefalse
tuition_ordering_ack_bill_key | UNIQUE (tuition_bill_id) | truefalsefalse
tuition_ordering_ack_events_pkey | PRIMARY KEY (id) | truefalsefalse
tuition_ordering_ack_identity_fkey | FOREIGN KEY (generation_identity_id) REFERENCES school_student_tuition_generation_identities(id) ON DELETE RESTRICT | truefalsefalse
tuition_ordering_ack_income_fkey | FOREIGN KEY (income_record_id) REFERENCES school_income_records(id) ON DELETE RESTRICT | truefalsefalse
tuition_ordering_ack_income_key | UNIQUE (income_record_id) | truefalsefalse
tuition_ordering_ack_manifest_check | CHECK ((expected_generation_manifest_sha256 ~ ''^[0-9a-f]{64}$''::text)) | truefalsefalse
tuition_ordering_ack_operator_check | CHECK ((btrim(operator_authority) <> ''''::text)) | truefalsefalse
tuition_ordering_ack_operator_source_check | CHECK ((operator_authority_source = ANY (ARRAY[''request_jwt_claim_sub''::text, ''tuition_operator_authority''::text, ''fallback_current_user''::text, ''fallback_literal''::text]))) | truefalsefalse
tuition_ordering_ack_precondition_check | CHECK ((jsonb_typeof(precondition_evidence) = ''object''::text)) | truefalsefalse
tuition_ordering_ack_reason_check | CHECK ((btrim(reason) <> ''''::text)) | truefalsefalse
tuition_ordering_ack_result_check | CHECK ((jsonb_typeof(result_evidence) = ''object''::text)) | truefalsefalse
tuition_ordering_ack_revision_fkey | FOREIGN KEY (generation_revision_id) REFERENCES school_student_tuition_generation_revisions(id) ON DELETE RESTRICT | truefalsefalse
tuition_ordering_ack_revision_key | UNIQUE (generation_revision_id) | truefalsefalse' THEN
    RAISE EXCEPTION 'VR_ACK_CONSTRAINT_DEFS:%s%s', chr(10), v_txt;
  END IF;
  -- ⑤ 的结构半边就在上面这份里：revision_key 必须是 UNIQUE (generation_revision_id)。
  -- 写路径的负例只能证明「某个 UNIQUE 拦住了」，证明不了是哪一列。

  -- 列：类型 / NOT NULL / 默认值（全列 NOT NULL 且无 DEFAULT，照抄 void_events）
  SELECT string_agg(a.attname||' '||format_type(a.atttypid,a.atttypmod)||' '
                    ||a.attnotnull::text||' '||coalesce(pg_get_expr(d.adbin,d.adrelid),'-'),
                    E'\n' ORDER BY a.attnum) INTO v_txt
    FROM pg_attribute a
    LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
   WHERE a.attrelid='public.school_student_tuition_generation_ordering_ack_events'::regclass AND a.attnum>0 AND NOT a.attisdropped;
  IF v_txt IS DISTINCT FROM
'id uuid true -
generation_identity_id uuid true -
generation_revision_id uuid true -
tuition_bill_id uuid true -
income_record_id uuid true -
expected_generation_manifest_sha256 text true -
reason text true -
operator_authority text true -
operator_authority_source text true -
precondition_evidence jsonb true -
result_evidence jsonb true -
created_at timestamp with time zone true -' THEN
    RAISE EXCEPTION 'VR_ACK_COLUMNS:%s%s', chr(10), v_txt;
  END IF;

  -- 触发器：实际定义 + 启用状态（tgenabled='O' 才是启用）
  SELECT string_agg(pg_get_triggerdef(oid)||' ||enabled='||tgenabled::text,
                    E'\n' ORDER BY tgname) INTO v_txt
    FROM pg_trigger WHERE tgrelid='public.school_student_tuition_generation_ordering_ack_events'::regclass AND NOT tgisinternal;
  IF v_txt IS DISTINCT FROM
'CREATE TRIGGER school_tuition_ordering_ack_event_delete_statement_guard BEFORE DELETE ON public.school_student_tuition_generation_ordering_ack_events FOR EACH STATEMENT EXECUTE FUNCTION school_guard_tuition_ordering_ack_event_delete() ||enabled=O
CREATE TRIGGER school_tuition_ordering_ack_event_immutable BEFORE DELETE OR UPDATE ON public.school_student_tuition_generation_ordering_ack_events FOR EACH ROW EXECUTE FUNCTION school_guard_tuition_ordering_ack_event_immutable() ||enabled=O
CREATE TRIGGER school_tuition_ordering_ack_event_truncate_forbidden BEFORE TRUNCATE ON public.school_student_tuition_generation_ordering_ack_events FOR EACH STATEMENT EXECUTE FUNCTION school_guard_tuition_ordering_ack_event_delete() ||enabled=O' THEN
    RAISE EXCEPTION 'VR_ACK_TRIGGER_DEFS:%s%s', chr(10), v_txt;
  END IF;

  -- 触发器所调用的两个守卫函数本身也要核 —— 触发器挂着而函数被改写，
  -- 上面的定义比对不会有任何变化。写路径只能证明三种语句被拒，
  -- 【证明不了每个分支都执行过】，未执行的分支由这里的结构断言兜住。
  SELECT string_agg(proname||' '||md5(pg_get_functiondef(oid)), E'\n' ORDER BY proname)
    INTO v_txt FROM pg_proc
   WHERE proname IN ('school_guard_tuition_ordering_ack_event_immutable',
                     'school_guard_tuition_ordering_ack_event_delete');
  IF v_txt IS DISTINCT FROM
'school_guard_tuition_ordering_ack_event_delete 8c8bd6cc922216de7c28eab67360e96f
school_guard_tuition_ordering_ack_event_immutable c54ee90eec419fee635ef577626e2695' THEN
    RAISE EXCEPTION 'VR_ACK_GUARD_FUNCTIONS:%s%s', chr(10), v_txt;
  END IF;

  -- 五个写路径函数各自只能有一个重载。md5 比对走精确签名，
  -- 多出来的同名重载它看不见，而 PostgREST 要到调用时才报
  -- function ... is not unique —— 那时账单已经开不出来了。
  SELECT string_agg(p.proname||' '||c.n::text, E'\n' ORDER BY p.proname) INTO v_txt
    FROM (VALUES
      ('school_build_student_tuition_generation_snapshot'),
      ('school_generate_student_tuition_bill_atomic'),
      ('school_generate_student_tuition_bill_atomic_core'),
      ('school_generate_student_tuition_bill_atomic_base_core_v1'),
      ('school_generate_student_tuition_next_revision_core')
    ) AS p(proname)
    CROSS JOIN LATERAL (
      SELECT count(*) AS n FROM pg_proc pp
        JOIN pg_namespace nn ON nn.oid = pp.pronamespace
       WHERE nn.nspname = 'public' AND pp.proname = p.proname
    ) c;
  IF v_txt IS DISTINCT FROM
'school_build_student_tuition_generation_snapshot 1
school_generate_student_tuition_bill_atomic 1
school_generate_student_tuition_bill_atomic_base_core_v1 1
school_generate_student_tuition_bill_atomic_core 1
school_generate_student_tuition_next_revision_core 1' THEN
    -- 本文件其余断言写的是 '%s%s'，在 PL/pgSQL 里那是「% 代入 + 字面 s」，
    -- 会在报文里多出一个 s。相邻的 %% 又是转义成字面 %，所以这里用
    -- 单占位符 + 拼接。
    --
    -- 比对只按「名字 + 数量」，签名【只进报文不进基线】：签名基线已由
    -- §1 的 md5 与返回契约断言各自守着，在这里再钉一份只会重复且更脆。
    -- 但只报「有 2 个」，看到的人还得自己再查一次才知道多出来的是什么。
    RAISE EXCEPTION 'VR_OVERLOAD_NOT_UNIQUE:%', chr(10)||v_txt||chr(10)||'实际签名:'||chr(10)||
      (SELECT string_agg(pp.proname||'('||pg_get_function_identity_arguments(pp.oid)||')',
                         chr(10) ORDER BY pp.proname, pp.oid)
         FROM pg_proc pp JOIN pg_namespace nn ON nn.oid = pp.pronamespace
        WHERE nn.nspname = 'public' AND pp.proname IN (
          'school_build_student_tuition_generation_snapshot',
          'school_generate_student_tuition_bill_atomic',
          'school_generate_student_tuition_bill_atomic_core',
          'school_generate_student_tuition_bill_atomic_base_core_v1',
          'school_generate_student_tuition_next_revision_core'));
  END IF;

  -- 授权照抄 void_events：service_role 只读，authenticated / anon 无权限
  SELECT coalesce(relacl::text,'') INTO v_txt FROM pg_class
   WHERE oid='public.school_student_tuition_generation_ordering_ack_events'::regclass;
  IF v_txt <> '{postgres=arwdDxtm/postgres,service_role=r/postgres}' THEN
    RAISE EXCEPTION 'VR_ACK_RELACL: %', v_txt; END IF;
  IF has_table_privilege('authenticated','public.school_student_tuition_generation_ordering_ack_events','SELECT')
     OR has_table_privilege('service_role','public.school_student_tuition_generation_ordering_ack_events','INSERT') THEN
    RAISE EXCEPTION 'VR_ACK_PRIVILEGE_WIDENED';
  END IF;

  SELECT relrowsecurity::text||'/'||relforcerowsecurity::text INTO v_txt
    FROM pg_class WHERE oid='public.school_student_tuition_generation_ordering_ack_events'::regclass;
  IF v_txt <> 'true/false' THEN RAISE EXCEPTION 'VR_ACK_RLS: %', v_txt; END IF;
  SELECT count(*) INTO v_n FROM pg_policies
   WHERE tablename='school_student_tuition_generation_ordering_ack_events';
  IF v_n <> 0 THEN RAISE EXCEPTION 'VR_ACK_POLICIES: 得 % 期望 0', v_n; END IF;

  -- 只读 reader
  IF to_regprocedure('public.school_get_tuition_generation_ordering_state(uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'VR_READER_MISSING'; END IF;
  SELECT coalesce(proacl::text,'') INTO v_txt FROM pg_proc
   WHERE oid=to_regprocedure('public.school_get_tuition_generation_ordering_state(uuid,text)');
  IF v_txt <> '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
    RAISE EXCEPTION 'VR_READER_ACL: %', v_txt; END IF;
  -- ACL 与 search_path 之外，定义本身与执行属性也要核：
  -- 一个被改写的 reader 仍可能保有正确的授权。
  SELECT md5(pg_get_functiondef(oid))||' secdef='||prosecdef::text||' vol='||provolatile::text
    INTO v_txt FROM pg_proc
   WHERE oid=to_regprocedure('public.school_get_tuition_generation_ordering_state(uuid,text)');
  IF v_txt IS DISTINCT FROM '6ff6f2b1b7ba79249a8467beb7c9561a secdef=true vol=s' THEN
    RAISE EXCEPTION 'VR_READER_DEFINITION: %', v_txt; END IF;
  SELECT coalesce(array_to_string(proconfig,','),'') INTO v_txt FROM pg_proc
   WHERE oid=to_regprocedure('public.school_get_tuition_generation_ordering_state(uuid,text)');
  IF v_txt <> 'search_path=pg_catalog, public' THEN
    RAISE EXCEPTION 'VR_READER_PROCONFIG: %', v_txt; END IF;

  RAISE NOTICE 'VR §3: ack 表约束定义 / 列定义 / 触发器定义与启用 / 守卫函数指纹 / 授权 / RLS / reader —— 通过';
END $vr$;

-- -----------------------------------------------------------------------------
-- §4 扫描：六个新键、reader 同源、各 effective_status 覆盖
-- -----------------------------------------------------------------------------
DO $vr$
DECLARE c record; v jsonb; v_rd boolean;
BEGIN
  FOR c IN
    SELECT DISTINCT l.student_id AS sid, to_char(l.lesson_date,'YYYY-MM') AS m
    FROM public.school_lesson_records l WHERE l.student_id IS NOT NULL
    UNION
    SELECT DISTINCT b.student_id, b.billing_month FROM public.school_student_tuition_bills b
  LOOP
    BEGIN
      SELECT to_jsonb(s) INTO STRICT v
      FROM public.school_build_student_tuition_generation_snapshot(c.sid,c.m,0.042) s;
    EXCEPTION WHEN OTHERS THEN
      -- 缺样本可以报「未验证」，但【非预期数据库异常必须失败】：
      -- 把程序缺陷（如返回结构错误）记成「一致的业务失败」等于放行。
      IF split_part(SQLERRM,':',1) NOT IN (
        'R2_F_B_CANDIDATES_EMPTY','R2_F_B_TARGET_SETTLEMENT_LOCKED',
        'R2_F_B_STUDENT_NOT_FOUND','R2_F_B_BUSINESS_ENTITY_REQUIRED',
        'R2_F_B_MULTIPLE_PREVIOUS_LOCKED_SETTLEMENTS','R2_F_B_BILLING_AMOUNT_INVALID',
        'R2_F_B_DUPLICATE_CANDIDATE_UUID','R2_F_B_CANDIDATE_CONTRACT_MISMATCH') THEN
        RAISE EXCEPTION 'VR_UNEXPECTED_BUILDER_ERROR (% %): %',
          c.sid, c.m, SQLERRM;
      END IF;
      INSERT INTO vr_scan VALUES(c.sid,c.m,false,SQLSTATE,split_part(SQLERRM,':',1),
        NULL,NULL,NULL,NULL);
      CONTINUE;
    END;
    -- reader 的失败集应是 builder 的子集：builder 成功时 reader 不该抛。
    BEGIN
      SELECT settlement_effective_complete INTO STRICT v_rd
      FROM public.school_get_tuition_generation_ordering_state(c.sid,c.m);
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'VR_READER_RAISED (% %): builder 成功而 reader 抛出 %',
        c.sid, c.m, SQLERRM;
    END;
    INSERT INTO vr_scan VALUES(c.sid,c.m,true,NULL,NULL,
      v->'carryover_evidence'->>'settlement_effective_status',
      (v->'carryover_evidence'->>'settlement_effective_complete')::boolean,
      v_rd,
      v->'carryover_evidence' ?& ARRAY[
        'settlement_effective_complete','settlement_effective_status','settlement_source_type',
        'settlement_source_id','settlement_provenance_carry_cny','settlement_blocker_code']);
  END LOOP;
END $vr$;

DO $vr$
DECLARE v_bad int; v_ok int;
BEGIN
  SELECT count(*) INTO v_ok FROM vr_scan WHERE ok;
  IF v_ok = 0 THEN
    RAISE EXCEPTION 'VR_COVERAGE_VACUOUS_B: builder 无成功样本，本节比对不构成验收';
  END IF;

  -- has_keys 为 NULL 时 NOT has_keys 得 NULL，不会被计入 —— 用 IS NOT TRUE
  SELECT count(*) INTO v_bad FROM vr_scan WHERE ok AND has_keys IS NOT TRUE;
  IF v_bad > 0 THEN RAISE EXCEPTION 'VR_EVIDENCE_KEYS_MISSING: % 个组合缺六个新键', v_bad; END IF;

  -- 同源断言：reader 与 builder 的结论必须一致。
  -- 【不排除 reader 返回 NULL】——builder 成功而 reader 给不出结论本身就是分叉。
  -- 两边都为 NULL 时 IS DISTINCT FROM 判为「相同」，会把「双方都无结论」
  -- 当成一致 —— 故先单独把 reader 无结论判失败。
  SELECT count(*) INTO v_bad FROM vr_scan WHERE ok AND reader_complete IS NULL;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'VR_READER_NO_VERDICT: % 个组合 builder 成功而 reader 无结论', v_bad;
  END IF;
  SELECT count(*) INTO v_bad FROM vr_scan
   WHERE ok AND reader_complete IS DISTINCT FROM eff_complete;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'VR_READER_DIVERGED: % 个组合 reader 与 builder 结论不一致', v_bad;
  END IF;

  RAISE NOTICE 'VR §4: 成功样本 % 个，六个新键齐全，reader 与 builder 结论一致 —— 通过', v_ok;
END $vr$;

-- -----------------------------------------------------------------------------
-- §5 ack 事件表内容完整性（若已有事件）
-- -----------------------------------------------------------------------------
DO $vr$
DECLARE v_n bigint; v_bad bigint;
BEGIN
  SELECT count(*) INTO v_n FROM public.school_student_tuition_generation_ordering_ack_events;
  RAISE NOTICE 'VR §5: ack 事件 % 条', v_n;
  IF v_n = 0 THEN
    RAISE WARNING 'VR_COVERAGE_ABSENT_ACK: 尚无 ack 事件，本节内容完整性【未被验收】';
    RETURN;
  END IF;

  -- 每条事件的 precondition 必须记录「上月未完成」——ack 只在守卫触发时才写
  SELECT count(*) INTO v_bad FROM public.school_student_tuition_generation_ordering_ack_events
   WHERE (precondition_evidence->>'settlement_effective_complete')::boolean IS NOT FALSE;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'VR_ACK_PRECONDITION_WRONG: % 条事件的前置事实不是「上月未完成」', v_bad;
  END IF;

  -- previous_settlement_month 必须非空——源键名是 settlement_month，
  -- 若当初按同名键直接读会得 NULL，这条就是那个错的探针。
  SELECT count(*) INTO v_bad FROM public.school_student_tuition_generation_ordering_ack_events
   WHERE nullif(btrim(coalesce(precondition_evidence->>'previous_settlement_month','')),'') IS NULL;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'VR_ACK_MONTH_NULL: % 条事件缺 previous_settlement_month  ← 键名映射错误', v_bad;
  END IF;

  -- 【四个 ID 必须同属一次生成】。外键只保证各自存在，不保证它们指向同一次。
  SELECT count(*) INTO v_bad
    FROM public.school_student_tuition_generation_ordering_ack_events e
    LEFT JOIN public.school_student_tuition_generation_revisions r ON r.id = e.generation_revision_id
    LEFT JOIN public.school_student_tuition_bills b ON b.id = e.tuition_bill_id
   WHERE r.id IS NULL
      OR r.generation_identity_id IS DISTINCT FROM e.generation_identity_id
      OR r.tuition_bill_id        IS DISTINCT FROM e.tuition_bill_id
      OR b.id IS NULL
      OR b.income_record_id       IS DISTINCT FROM e.income_record_id;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'VR_ACK_IDS_INCOHERENT: % 条事件的四个 ID 不属于同一次生成', v_bad;
  END IF;

  -- manifest 必须等于该 revision 冻结的 manifest
  SELECT count(*) INTO v_bad
    FROM public.school_student_tuition_generation_ordering_ack_events e
    JOIN public.school_student_tuition_generation_revisions r ON r.id = e.generation_revision_id
   WHERE e.expected_generation_manifest_sha256 IS DISTINCT FROM r.generation_manifest_sha256;
  IF v_bad > 0 THEN RAISE EXCEPTION 'VR_ACK_MANIFEST_MISMATCH: % 条', v_bad; END IF;

  -- 【月份非空还不够】：记错月份同样通不过。必须等于账单冻结的上月。
  SELECT count(*) INTO v_bad
    FROM public.school_student_tuition_generation_ordering_ack_events e
    JOIN public.school_student_tuition_bills b ON b.id = e.tuition_bill_id
   WHERE e.precondition_evidence->>'previous_settlement_month'
         IS DISTINCT FROM b.previous_settlement_month;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'VR_ACK_MONTH_MISMATCH: % 条事件的上月与账单冻结值不符', v_bad;
  END IF;

  RAISE NOTICE 'VR §5: ack 事件内容完整性 —— 通过';
END $vr$;

-- -----------------------------------------------------------------------------
-- §6 覆盖率报告
--     ⚠️ 出现 0 的行表示【该分支未被本脚本验收】，不是通过。
-- -----------------------------------------------------------------------------
\echo ''
\echo '--- 各 effective_status 覆盖（任一为 0 ⇒ 该分支未验证）---'
SELECT s.expected AS effective_status, count(v.*) AS combos
FROM (VALUES ('ordinary_locked'),('historically_consumed_immutable'),
             ('historical_zero_carry_complete'),('incomplete')) AS s(expected)
LEFT JOIN vr_scan v ON v.eff_status = s.expected AND v.ok
GROUP BY s.expected ORDER BY 2 DESC, 1;

\echo ''
\echo '--- builder 失败样本按错误码（不得被笼统吞掉）---'
SELECT sqlstate, errcode, count(*) FROM vr_scan WHERE NOT ok GROUP BY 1,2 ORDER BY 3 DESC;

\echo ''
\echo '--- ack 事件的操作者来源分布 ---'
\echo '    fallback_* 表示未能识别具体操作人，只证明函数以自身执行身份回退。'
SELECT operator_authority_source, operator_authority, count(*)
FROM public.school_student_tuition_generation_ordering_ack_events
GROUP BY 1,2 ORDER BY 3 DESC;

ROLLBACK;
DROP TABLE IF EXISTS pg_temp.vr_scan;
\echo ''
\echo '=== 只读验收结束（事务已 ROLLBACK，未写入任何业务数据）==='
\echo '⚠️ 仍未由本脚本覆盖：HTTP 层重载解析、并发窗口、P0-E 写路径。'
