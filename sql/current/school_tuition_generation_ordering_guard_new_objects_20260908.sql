-- =============================================================================
-- 学费生成顺序守卫：新增对象（表 / 守卫函数 / 触发器 / 只读 reader）
--
-- 设计：~/aozora-security-20260827/school-generation-ordering-guard-design-20260908-v14.md
-- 取证：Codex R6–R15（2026-09-07 23:52 ～ 2026-09-08 10:08 JST）
--
-- 本文件只创建新对象，不修改任何既有函数。
-- 既有函数（B / G / C / F / N）的替换在 deploy 主文件，需生产 pg_get_functiondef 原文。
--
-- 幂等性：全文件可重复执行（DROP IF EXISTS + CREATE）。
-- 事务：调用方负责 BEGIN / COMMIT。本文件不自行提交。
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. 前置断言：新对象不得已存在（防止误覆盖）
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('public.school_student_tuition_generation_ordering_ack_events')
       IS NOT NULL THEN
    RAISE EXCEPTION 'ORDERING_ACK_TABLE_ALREADY_EXISTS: refusing to redefine';
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 1. ack 事件表
--
-- 结构照抄 school_student_tuition_generation_void_events（Codex R11 取证）：
--   全列 NOT NULL 无 DEFAULT / 主键 id / 三个独立 UNIQUE /
--   四个 FK ON DELETE RESTRICT 立即检查 / manifest 与非空白 CHECK /
--   evidence 为 jsonb object / 仅主键与三个 UNIQUE 索引
--
-- 与先例的两处【刻意分歧】——不是遗漏，勿「补齐」：
--
--   (1) ack 理由【只存本表】，不写进 bill / income 的列。
--       void 的理由同时写入 income.cancelled_reason + cancelled_by 与
--       bill.cancelled_reason + updated_by；ack 没有可用的既有列，
--       而【新增列已被排除】——school_compute_historical_tuition_registration_manifest
--       哈希 to_jsonb(v_bill) 整行，新增列会让 7 张 historical_registration_v1
--       账单的 bill_row_sha256 改变，validator 比较后抛
--       TUITION_HISTORICAL_REGISTRATION_REVISION_INVALID（Codex R11 逐张实测）。
--
--   (2) 新增 operator_authority_source 列。
--       F 与 N 的操作者来源【不是同一套机制】：
--         F: request.jwt.claim.sub -> 回退 current_user（= postgres）
--         N: school.tuition_operator_authority -> 回退字面值
--       不记来源就是把回退值伪装成身份。
-- -----------------------------------------------------------------------------
CREATE TABLE public.school_student_tuition_generation_ordering_ack_events (
  id                                  uuid        NOT NULL,
  generation_identity_id              uuid        NOT NULL,
  generation_revision_id              uuid        NOT NULL,
  tuition_bill_id                     uuid        NOT NULL,
  income_record_id                    uuid        NOT NULL,
  expected_generation_manifest_sha256 text        NOT NULL,
  reason                              text        NOT NULL,
  operator_authority                  text        NOT NULL,
  operator_authority_source           text        NOT NULL,
  precondition_evidence               jsonb       NOT NULL,
  result_evidence                     jsonb       NOT NULL,
  created_at                          timestamptz NOT NULL,

  CONSTRAINT tuition_ordering_ack_events_pkey
    PRIMARY KEY (id),

  -- 「一个 revision / bill / income 最多一条 ack」的结构保证。
  -- 幂等的第一道防线不是这里，而是 C 的幂等分支（已有 active revision 时
  -- 不进入 F/N，故不会重复消费 ack）。本约束是兜底，照抄 void 先例。
  CONSTRAINT tuition_ordering_ack_revision_key
    UNIQUE (generation_revision_id),
  CONSTRAINT tuition_ordering_ack_bill_key
    UNIQUE (tuition_bill_id),
  CONSTRAINT tuition_ordering_ack_income_key
    UNIQUE (income_record_id),

  -- 立即检查，不可延迟。
  -- 之所以【不需要】DEFERRABLE：插入点统一在 C，而 C 在 generation identity
  -- 与 revision 均已创建/取得之后才插入，被引用行必然已存在。
  -- 若改在 F 内插入则不可行——C 在 F 返回后才 gen_random_uuid()，
  -- F 连 UUID 都还没有，延迟外键只延迟存在性检查，不会填入后来产生的 ID。
  CONSTRAINT tuition_ordering_ack_identity_fkey
    FOREIGN KEY (generation_identity_id)
    REFERENCES public.school_student_tuition_generation_identities(id)
    ON DELETE RESTRICT,
  CONSTRAINT tuition_ordering_ack_revision_fkey
    FOREIGN KEY (generation_revision_id)
    REFERENCES public.school_student_tuition_generation_revisions(id)
    ON DELETE RESTRICT,
  CONSTRAINT tuition_ordering_ack_bill_fkey
    FOREIGN KEY (tuition_bill_id)
    REFERENCES public.school_student_tuition_bills(id)
    ON DELETE RESTRICT,
  CONSTRAINT tuition_ordering_ack_income_fkey
    FOREIGN KEY (income_record_id)
    REFERENCES public.school_income_records(id)
    ON DELETE RESTRICT,

  CONSTRAINT tuition_ordering_ack_manifest_check
    CHECK (expected_generation_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  CONSTRAINT tuition_ordering_ack_reason_check
    CHECK (btrim(reason) <> ''),
  CONSTRAINT tuition_ordering_ack_operator_check
    CHECK (btrim(operator_authority) <> ''),

  -- 来源标签由【身份取值实际走的分支】决定，不由 trim 结果决定。
  -- trim 只作用于 ack 理由；身份逐字沿用所在函数既有的 nullif(...,'') 不 trim 逻辑。
  CONSTRAINT tuition_ordering_ack_operator_source_check
    CHECK (operator_authority_source IN (
      'request_jwt_claim_sub',        -- F 路径，JWT 有值
      'tuition_operator_authority',   -- N 路径，事务上下文有值
      'fallback_current_user',        -- F 路径回退（实际多为 postgres）
      'fallback_literal'              -- N 路径回退（service_role_v2_operations_v1）
    )),

  CONSTRAINT tuition_ordering_ack_precondition_check
    CHECK (jsonb_typeof(precondition_evidence) = 'object'),
  CONSTRAINT tuition_ordering_ack_result_check
    CHECK (jsonb_typeof(result_evidence) = 'object')
);

COMMENT ON TABLE public.school_student_tuition_generation_ordering_ack_events IS
  'Ordering-guard acknowledgements. One row per generation revision that was allowed '
  'to proceed while the previous settlement month was not effectively complete. '
  'Reason lives only here: no equivalent bill/income column exists and adding one '
  'would change to_jsonb(bill) for historical_registration_v1 rows. '
  'operator_authority is NOT a verified end-user identity; see operator_authority_source.';

COMMENT ON COLUMN public.school_student_tuition_generation_ordering_ack_events
  .operator_authority_source IS
  'Which branch produced operator_authority. fallback_current_user means the '
  'SECURITY DEFINER function fell back to its own execution identity (postgres); '
  'it does not identify the human operator and does not prove the caller holds owner rights.';

-- -----------------------------------------------------------------------------
-- 2. 不可变守卫函数
--
-- 【刻意不带 fixture 例外】。先例的两个守卫函数
-- （school_guard_p0c_generation_direct_delete /
--   school_guard_tuition_generation_void_event_immutable）原文都含绑定
-- 2026-08-03 具体测试 UUID 的例外（tuition.p0c_fixture_cleanup /
-- tuition.p0d_fixture_cleanup）。那些例外与本表无关。
--
-- 兼容性边界（Codex R13 取证，如实记录）：
--   兼容   local-prodlike-harness/bootstrap.sh 的整库重建
--   不兼容 P0-C / P0-D 的逐行 fixture 清理：若那些 fixture 产生过【已提交】ack，
--          本表禁止删除事件，且四个 FK 为 RESTRICT，会阻止删除被引用对象。
--   未证明既有 fixture 一定触发 ack，也未运行清理测试。
--   ——不为此在生产上添加清理后门。
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.school_guard_tuition_ordering_ack_event_immutable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  raise exception 'TUITION_ORDERING_ACK_EVENT_IMMUTABLE';
end
$function$;

CREATE OR REPLACE FUNCTION public.school_guard_tuition_ordering_ack_event_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  raise exception 'TUITION_ORDERING_ACK_EVENT_DELETE_FORBIDDEN';
end
$function$;

DROP TRIGGER IF EXISTS school_tuition_ordering_ack_event_immutable
  ON public.school_student_tuition_generation_ordering_ack_events;
CREATE TRIGGER school_tuition_ordering_ack_event_immutable
  BEFORE UPDATE OR DELETE
  ON public.school_student_tuition_generation_ordering_ack_events
  FOR EACH ROW
  EXECUTE FUNCTION public.school_guard_tuition_ordering_ack_event_immutable();

DROP TRIGGER IF EXISTS school_tuition_ordering_ack_event_delete_statement_guard
  ON public.school_student_tuition_generation_ordering_ack_events;
CREATE TRIGGER school_tuition_ordering_ack_event_delete_statement_guard
  BEFORE DELETE
  ON public.school_student_tuition_generation_ordering_ack_events
  EXECUTE FUNCTION public.school_guard_tuition_ordering_ack_event_delete();

DROP TRIGGER IF EXISTS school_tuition_ordering_ack_event_truncate_forbidden
  ON public.school_student_tuition_generation_ordering_ack_events;
CREATE TRIGGER school_tuition_ordering_ack_event_truncate_forbidden
  BEFORE TRUNCATE
  ON public.school_student_tuition_generation_ordering_ack_events
  EXECUTE FUNCTION public.school_guard_tuition_ordering_ack_event_delete();

-- -----------------------------------------------------------------------------
-- 3. 表授权：照抄 void_events
--   {postgres=arwdDxtm/postgres,service_role=r/postgres}
--   service_role 只读、无 INSERT；authenticated / anon 无任何权限。
--   RLS 启用、FORCE=false、零策略（依赖 owner 与 service_role 的 BYPASSRLS）。
--
-- 业务负责人 2026-09-08 已确认：ack 事实前端不可见可以接受。
-- 日后若要在界面显示「何时确认过、理由是什么」，另加只读函数即可，是纯加法。
-- -----------------------------------------------------------------------------
ALTER TABLE public.school_student_tuition_generation_ordering_ack_events
  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_student_tuition_generation_ordering_ack_events
  NO FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.school_student_tuition_generation_ordering_ack_events
  FROM PUBLIC;
REVOKE ALL ON TABLE public.school_student_tuition_generation_ordering_ack_events
  FROM authenticated;
REVOKE ALL ON TABLE public.school_student_tuition_generation_ordering_ack_events
  FROM anon;
REVOKE ALL ON TABLE public.school_student_tuition_generation_ordering_ack_events
  FROM service_role;
GRANT SELECT ON TABLE public.school_student_tuition_generation_ordering_ack_events
  TO service_role;

-- -----------------------------------------------------------------------------
-- 4. 只读 reader：供前端渲染「上月结算是否完成」
--
-- 为什么不改 school_get_student_tuition_validation_preview_details（V）：
--   V 的 28 个返回列【不含 carryover_evidence】（Codex R6 取证），
--   加列须 DROP + CREATE 一个 authenticated 可执行的函数；
--   且 V 有 R2_F_B_ALREADY_BILLED 早退分支，不总走到 builder。
--   新增 reader 是纯加法，rollback 只需 DROP。
--
-- 【必须与 builder 同源】——以下三段逐字复制 B 的原文，一个字符都不改：
--   (1) v_month 规范化 nullif(pg_catalog.btrim(coalesce(...,'')),'')
--   (2) 月份正则与 R2_F_B_BILLING_MONTH_INVALID
--   (3) v_previous_month 的 to_char/to_date - interval '1 month'
--   (4) 学生查询含 AND student.app_type='school'
--       ——漏掉会让 reader 对非 school 学生返回结果而 B 报不存在，直接分叉。
--
-- 【刻意不复制】B 的 R2_F_B_TARGET_SETTLEMENT_LOCKED 等后续检查：
--   本 reader 只回答「上月是否完成」，不预判本月能否生成。
--   因此 reader 的失败集是 B 的【子集】，两者错误优先级本就不同
--   （B 在查学生【之前】先校验汇率；本 reader 没有汇率参数）。
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.school_get_tuition_generation_ordering_state(
  p_student_id uuid,
  p_billing_month text
)
RETURNS TABLE(
  student_id uuid,
  business_entity_id uuid,
  billing_month text,
  previous_settlement_month text,
  settlement_effective_complete boolean,
  settlement_effective_status text,
  settlement_blocker_code text,
  settlement_provenance_carry_cny numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_month text := nullif(pg_catalog.btrim(coalesce(p_billing_month,'')),'');
  v_previous_month text;
  v_student public.school_students%rowtype;
begin
  if p_student_id is null then
    raise exception 'R2_F_B_STUDENT_REQUIRED';
  end if;

  if v_month is null or v_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'R2_F_B_BILLING_MONTH_INVALID';
  end if;

  select student.* into v_student
  from public.school_students student
  where student.id=p_student_id and student.app_type='school';
  if not found then raise exception 'R2_F_B_STUDENT_NOT_FOUND'; end if;
  if v_student.business_entity_id is null then
    raise exception 'R2_F_B_BUSINESS_ENTITY_REQUIRED';
  end if;

  v_previous_month := pg_catalog.to_char(
    (pg_catalog.to_date(v_month||'-01','YYYY-MM-DD')-interval '1 month')::date,
    'YYYY-MM'
  );

  return query
  select
    p_student_id,
    v_student.business_entity_id,
    v_month,
    v_previous_month,
    r.effective_complete,
    r.effective_status,
    r.blocker_code,
    r.carry_cny
  from public.school_resolve_student_monthly_settlement_effective_state(
         p_student_id, v_previous_month, v_student.business_entity_id) r;
end
$function$;

COMMENT ON FUNCTION public.school_get_tuition_generation_ordering_state(uuid,text) IS
  'Read-only: is the previous settlement month effectively complete? Renders the '
  'ordering warning in the generation preview. Shares month normalisation, previous-month '
  'derivation and student lookup verbatim with school_build_student_tuition_generation_snapshot. '
  'Deliberately omits that function''s later checks (target month lock, candidates, amounts): '
  'this answers only the previous-month question, so its failure set is a subset.';

-- ⚠️ 逐条 GRANT，且顺序即基线顺序。一条 GRANT 带两个角色不行：
--    public schema 的默认授权会先把 service_role 放进 ACL 数组，
--    随后追加 authenticated ⇒ 顺序颠倒，与基线不符。
--    2026-09-10 的 VR_READER_ACL 就是这么来的。
REVOKE ALL ON FUNCTION public.school_get_tuition_generation_ordering_state(uuid,text)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.school_get_tuition_generation_ordering_state(uuid,text)
  FROM authenticated;
REVOKE ALL ON FUNCTION public.school_get_tuition_generation_ordering_state(uuid,text)
  FROM service_role;
GRANT EXECUTE ON FUNCTION public.school_get_tuition_generation_ordering_state(uuid,text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.school_get_tuition_generation_ordering_state(uuid,text)
  TO service_role;

-- =============================================================================
-- 本文件到此为止。
--
-- 尚未包含（需生产 pg_get_functiondef 原文，见 R16）：
--   B 加 resolver 调用与六个 evidence 键
--   G / C / F / N 的 DROP + CREATE（加参数、守卫、扩展返回列、C 显式投影 20 列）
--   md5 / ACL / proconfig / COMMENT / 参数默认值 的基线断言与还原
-- =============================================================================
