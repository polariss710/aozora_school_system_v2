-- School V2 匿名角色权限收口 —— 2026-08-28 已在生产执行
--
-- 目的
--   public / anon（未认证匿名角色）不应持有 school 业务对象的任何权限。
--   本系统全部前端功能均在登录后以 authenticated 身份访问，因此收回 anon
--   不影响既有功能。执行后已逐页冒烟验证，见文末。
--
-- 复现或重建环境时，执行前请先做这两项核对（勿省略）
--
--   一、先确认权限来源，再决定收 public 还是收 anon。PostgreSQL 语义：
--         revoke ... from anon    只撤销「直接授予 anon」的部分，不影响 PUBLIC
--         revoke ... from public  只撤销 PUBLIC，不影响「直接授予 anon」的部分
--       二者互不覆盖。本文件第一部分的权限来自 PUBLIC（ACL 形如 `=X/postgres`），
--       第二、三部分为直接授予 anon（`anon=arwdDxtm`）——同一批对象上两种来源
--       都出现过，必须逐类确认，不能一律照抄。
--
--       判据请用 proacl / relacl 直接匹配，例如
--         array_to_string(proacl, ',') ~ '(^|,)=X'     -- 有无 PUBLIC 项
--       不要用 has_function_privilege() / has_table_privilege() 做验证：
--       它们把继承来的权限也算作有权限，收 PUBLIC 时既测不出成功也测不出失败。
--
--   二、确认 authenticated 在对应对象上持有独立授权（ACL 中有
--       `authenticated=...` 项），否则收回 PUBLIC 会连带断掉登录用户。
--       本次执行前已确认全部对象满足该条件。
--
-- 结构
--   第一部分  写函数 23 个    —— 权限来自 PUBLIC
--   第二部分  表 12 张        —— 10 张 V1 遗留空表 + 2 张在用表
--   第三部分  读对象 31 个    —— 表与视图，权限均为直接授予 anon
--
-- 未纳入本次范围
--   school_create_cash_income_confirmation
--   school_request_cash_income_confirmation
--   school_update_personal_cash_income_linkage_event_status
--   这三个函数在本仓库前端无调用点，疑似由联动的 Home/Cash 系统调用，
--   需先确认该侧调用身份，故本次保留。
--
-- 回滚脚本按执行时各对象实际持有的权限逐条生成，保存在执行者本地。

\set ON_ERROR_STOP on

begin;

-- ===========================================================================
-- 第一部分：写函数（23 个）
--
-- 这些函数均为 SECURITY DEFINER，函数体内不含 auth.uid() / membership 查询等
-- 身份校验。注意其中若干函数调用了 school_assert_new_business_entity_allowed
-- 或 school_require_feature_gate_state —— 那是业务规则检查，不做身份校验，
-- 不能视为权限防护。
-- ===========================================================================

revoke execute on function public.school_cancel_pending_income_record(p_income_id uuid, p_cancel_reason text, p_operator text) from public;
revoke execute on function public.school_create_account_adjustment(p_adjustment_date date, p_business_entity_id uuid, p_account_id uuid, p_amount numeric, p_reason text, p_note text) from public;
revoke execute on function public.school_create_account_profile(p_account_code text, p_name text, p_account_type text, p_currency text, p_business_entity_id uuid, p_is_company_account boolean, p_is_active boolean, p_note text) from public;
revoke execute on function public.school_create_account_profile(p_account_code text, p_name text, p_initial_balance numeric, p_account_type text, p_currency text, p_business_entity_id uuid, p_is_company_account boolean, p_is_active boolean, p_note text) from public;
revoke execute on function public.school_create_account_profile(p_account_code text, p_name text, p_initial_balance numeric, p_account_type text, p_currency text, p_business_entity_id uuid, p_is_company_account boolean, p_is_active boolean, p_note text, p_app_type text) from public;
revoke execute on function public.school_create_account_transfer(p_transfer_date date, p_business_entity_id uuid, p_from_account_id uuid, p_to_account_id uuid, p_amount numeric, p_reason text, p_note text) from public;
revoke execute on function public.school_create_income_record(p_income_date date, p_settlement_month text, p_business_entity_id uuid, p_student_id uuid, p_account_id uuid, p_amount numeric, p_income_category text, p_description text, p_currency text, p_payment_currency text, p_exchange_rate numeric, p_payment_method text, p_is_taxable_income boolean, p_tax_category text, p_receipt_status text, p_include_in_student_settlement boolean, p_note text) from public;
revoke execute on function public.school_create_pending_cash_income_record(p_income_date date, p_settlement_month text, p_business_entity_id uuid, p_student_id uuid, p_amount numeric, p_income_category text, p_description text, p_currency text, p_payment_currency text, p_exchange_rate numeric, p_is_taxable_income boolean, p_tax_category text, p_receipt_status text, p_note text) from public;
revoke execute on function public.school_create_subject_profile(p_name text, p_status text, p_category text, p_primary_category text, p_tertiary_category text, p_color text, p_sort_order integer, p_note text) from public;
revoke execute on function public.school_create_teacher_profile(p_profile jsonb) from public;
revoke execute on function public.school_create_teacher_profile(p_display_name text, p_teacher_code text, p_name text, p_kana_name text, p_status text, p_department text, p_default_business_entity_id uuid, p_note text) from public;
revoke execute on function public.school_reverse_account_adjustment(p_adjustment_id uuid, p_reversal_date date, p_reason text) from public;
revoke execute on function public.school_reverse_account_transfer(p_transfer_id uuid, p_reversal_date date, p_reason text) from public;
revoke execute on function public.school_reverse_income_record(p_income_id uuid, p_reversal_date date, p_reason text) from public;
revoke execute on function public.school_update_account_profile(p_account_id uuid, p_name text, p_account_type text, p_is_company_account boolean, p_is_active boolean, p_note text) from public;
revoke execute on function public.school_update_account_profile(p_account_id uuid, p_name text, p_currency text, p_account_type text, p_business_entity_id uuid, p_is_company_account boolean, p_is_active boolean, p_note text) from public;
revoke execute on function public.school_update_account_profile(p_account_id uuid, p_name text, p_currency text, p_account_type text, p_business_entity_id uuid, p_is_company_account boolean, p_is_active boolean, p_note text, p_app_type text) from public;
revoke execute on function public.school_update_income_record(p_income_id uuid, p_income_date date, p_settlement_month text, p_business_entity_id uuid, p_student_id uuid, p_account_id uuid, p_amount numeric, p_income_category text, p_description text, p_currency text, p_payment_currency text, p_exchange_rate numeric, p_payment_method text, p_is_taxable_income boolean, p_tax_category text, p_receipt_status text, p_include_in_student_settlement boolean, p_note text) from public;
revoke execute on function public.school_update_subject_profile(p_subject_id uuid, p_name text, p_status text, p_note text) from public;
revoke execute on function public.school_update_subject_profile(p_subject_id uuid, p_name text, p_status text, p_category text, p_primary_category text, p_tertiary_category text, p_color text, p_sort_order integer, p_note text) from public;
revoke execute on function public.school_update_teacher_profile(p_teacher_id uuid, p_profile jsonb) from public;
revoke execute on function public.school_update_teacher_profile(p_teacher_id uuid, p_display_name text, p_status text, p_default_business_entity_id uuid, p_note text) from public;
revoke execute on function public.school_update_teacher_profile(p_teacher_id uuid, p_display_name text, p_name text, p_kana_name text, p_department text, p_status text, p_default_hourly_rate numeric, p_default_currency text, p_default_payment_currency text, p_default_payment_method text, p_default_business_entity_id uuid, p_note text) from public;

-- ===========================================================================
-- 第二部分：表（12 张）
--
-- 前 10 张为 V1 遗留表：代码零引用、count(*) = 0、pg_stat 累计读写为 0。
-- V2 对应功能已迁至 school_lesson_records 等。未删表，仅收权限。
--
-- 后 2 张仍在使用（前端 account-transaction-detail 页经 .from(config.table)
-- 动态查表），且 ACL 中 anon 与 authenticated 均为独立授权，
-- 故仅收 anon，保留 authenticated。
-- ===========================================================================

revoke all on table public.school_actual_lessons from public, anon, authenticated;
revoke all on table public.school_planned_lessons from public, anon, authenticated;
revoke all on table public.school_lesson_schedules from public, anon, authenticated;
revoke all on table public.school_schedule_students from public, anon, authenticated;
revoke all on table public.school_student_months from public, anon, authenticated;
revoke all on table public.school_teacher_work_logs from public, anon, authenticated;
revoke all on table public.school_monthly_reports from public, anon, authenticated;
revoke all on table public.school_student_payments from public, anon, authenticated;
revoke all on table public.school_import_batches from public, anon, authenticated;
revoke all on table public.school_import_errors from public, anon, authenticated;
revoke all on table public.school_account_adjustments from anon;
revoke all on table public.school_account_transfers from anon;

-- ===========================================================================
-- 第三部分：读对象（31 个表与视图）
--
-- 注意其中 4 个为视图：school_operational_income_records、
-- school_v_business_month_summary、school_v_student_month_summary、
-- school_v_teacher_salary_month_summary。
-- 视图不受 RLS 保护，权限完全由 grant 决定 —— 盘点时若只查 relkind='r'
-- 会把它们漏掉。
-- ===========================================================================

revoke all on backup_v51_accounts from anon;
revoke all on backup_v51_expense_records from anon;
revoke all on backup_v51_reimbursement_items from anon;
revoke all on backup_v51_reimbursements from anon;
revoke all on school_expense_attachments from anon;
revoke all on school_income_records from anon;
revoke all on school_lesson_records from anon;
revoke all on school_operational_income_records from anon;
revoke all on school_payment_requests from anon;
revoke all on school_personal_cash_account_mappings from anon;
revoke all on school_personal_cash_income_linkage_events from anon;
revoke all on school_personal_cash_linkage_events from anon;
revoke all on school_reimbursement_expenses from anon;
revoke all on school_reimbursement_items from anon;
revoke all on school_reimbursements from anon;
revoke all on school_salary_payments from anon;
revoke all on school_settings from anon;
revoke all on school_student_monthly_settlements from anon;
revoke all on school_student_settlement_adjustment_drafts from anon;
revoke all on school_student_settlement_adjustments from anon;
revoke all on school_student_settlement_carryovers from anon;
revoke all on school_student_tuition_bills from anon;
revoke all on school_subjects from anon;
revoke all on school_teacher_wage_detail_adjustments from anon;
revoke all on school_teacher_wage_lock_details from anon;
revoke all on school_teacher_wage_locks from anon;
revoke all on school_teacher_wage_rules from anon;
revoke all on school_teachers from anon;
revoke all on school_v_business_month_summary from anon;
revoke all on school_v_student_month_summary from anon;
revoke all on school_v_teacher_salary_month_summary from anon;

commit;

-- ===========================================================================
-- 执行后验证（全部通过）
-- ===========================================================================
--
--   anon 可执行的写函数        0（仅剩上述 3 个 cash 函数）
--   anon 可增删改的表          0
--   anon 可读的表 / 视图       0
--   authenticated 保有授权     未变
--
-- 冒烟测试（admin 账号，全部正常）
--   income / account / teacher / subject                  写操作各一次
--   account-transaction-detail（账户调整明细）             动态查表路径
--   lesson / expense / wage / reimbursement / settlement   列表加载
--
-- 后续仍需处理
--   1. 上述 3 个 cash 联动函数
--   2. RLS policy 中仍含 anon / public 的条目 —— grant 已收，policy 为残留，
--      不构成访问路径，可择期清理
--   3. 新增角色时，正确的 policy 写法参见 school_students /
--      school_business_entities：
--        EXISTS (SELECT 1 FROM school_get_current_app_membership()
--                      membership(user_id, role, is_active)
--                WHERE membership.is_active
--                  AND membership.role = ANY (ARRAY['admin','operator','read_only']))
--      全项目仅此二者以 membership role 为判据，其余表的 policy 均为 using(true)。
-- ===========================================================================
