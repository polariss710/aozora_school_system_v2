-- school_tuition_r0_feature_gate_state.sql
-- R0 configuration only. Writes exactly three feature-gate rows and no
-- student, lesson, bill, income, Cash, account, settlement, or wage data.

begin;

insert into public.school_feature_gates (
  feature_key,
  state,
  reason,
  release_version,
  evidence_hash,
  updated_at,
  updated_by
)
values
  (
    'student_tuition_preview',
    'validation_preview_only',
    '学费链资金一致性整改期间仅允许只读验证预览。',
    'r0-20260727',
    null,
    now(),
    current_user
  ),
  (
    'student_tuition_generate',
    'blocked',
    '学费应收生成正在进行资金一致性整改，禁止生成正式账单或收入。',
    'r0-20260727',
    null,
    now(),
    current_user
  ),
  (
    'student_tuition_cash_submit',
    'blocked',
    'student_tuition_bill 来源的 pending 收入禁止提交 Cash。',
    'r0-20260727',
    null,
    now(),
    current_user
  )
on conflict (feature_key) do update
set state = excluded.state,
    reason = excluded.reason,
    release_version = excluded.release_version,
    evidence_hash = excluded.evidence_hash,
    updated_at = excluded.updated_at,
    updated_by = excluded.updated_by;

commit;
