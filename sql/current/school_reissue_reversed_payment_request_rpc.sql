-- 用途：
-- reversed payment request 重新生成新的 pending payment request。
--
-- 安全边界：
-- - 不会生成 school_expense_records。
-- - 不会生成 school_account_transactions。
-- - 不会修改 school_accounts.current_balance。
-- - 不会修改老师工资锁定。
-- - 不会删除任何记录。
-- - 不会把原 reversed 请求改回 pending。
-- - 原 reversed 请求保留为审计记录。
--
-- 关联字段使用约定：
-- - 原 reversed 请求 A 写入 replacement_payment_request_id，指向新 pending 请求 B。
-- - 新 pending 请求 B 写入 reissued_from_payment_request_id，指向原 reversed 请求 A。
-- - reissue_reason / reissued_at 存储在新 pending 请求 B 上，表示 B 的生成原因和生成时间。

alter table public.school_payment_requests
  add column if not exists reissued_from_payment_request_id uuid null,
  add column if not exists replacement_payment_request_id uuid null,
  add column if not exists reissue_reason text null,
  add column if not exists reissued_at timestamptz null;

create index if not exists idx_school_payment_requests_reissued_from
  on public.school_payment_requests(reissued_from_payment_request_id);

create index if not exists idx_school_payment_requests_replacement
  on public.school_payment_requests(replacement_payment_request_id);

-- 防重复策略：
-- 一个原 reversed request 只能生成一个 replacement。
-- 使用新记录 B 的 reissued_from_payment_request_id 做 partial unique index，
-- 因为它直接表达“谁是从哪个原请求重新生成的”，并且可防止并发重复插入。
create unique index if not exists uq_school_payment_requests_reissued_from
  on public.school_payment_requests(reissued_from_payment_request_id)
  where reissued_from_payment_request_id is not null;

create or replace function public.school_reissue_reversed_payment_request(
  p_payment_request_id uuid,
  p_reason text default null
)
returns table(
  original_payment_request_id uuid,
  new_payment_request_id uuid,
  old_status text,
  new_status text,
  reissued_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_original public.school_payment_requests%rowtype;
  v_new_id uuid;
  v_reissued_at timestamptz := now();
  v_existing_reissue_id uuid;
  v_note text;
begin
  perform public.school_require_current_app_admin();

  if p_payment_request_id is null then
    raise exception 'payment request id is required';
  end if;

  select *
  into v_original
  from public.school_payment_requests
  where id = p_payment_request_id
  for update;

  if not found then
    raise exception 'payment request not found: %', p_payment_request_id;
  end if;

  if v_original.status <> 'reversed' then
    raise exception 'payment request status must be reversed. current status: %', v_original.status;
  end if;

  if v_original.replacement_payment_request_id is not null then
    raise exception 'payment request is already reissued: %', v_original.replacement_payment_request_id;
  end if;

  select id
  into v_existing_reissue_id
  from public.school_payment_requests
  where reissued_from_payment_request_id = v_original.id
  limit 1;

  if v_existing_reissue_id is not null then
    raise exception 'payment request already has replacement: %', v_existing_reissue_id;
  end if;

  v_note := concat_ws(
    E'\n',
    nullif(v_original.note, ''),
    '由撤销支付请求重新生成：原请求ID ' || v_original.id::text,
    case
      when nullif(trim(coalesce(p_reason, '')), '') is not null
        then '重新生成原因：' || trim(p_reason)
      else null
    end
  );

  insert into public.school_payment_requests (
    source_type,
    source_id,
    request_month,
    payee_type,
    payee_id,
    payee_name,
    business_entity_id,
    business_name,
    currency,
    amount,
    amount_jpy,
    amount_cny,
    status,
    due_date,
    paid_at,
    note,
    created_at,
    updated_at,
    paid_expense_id,
    paid_account_transaction_id,
    account_id,
    reversed_at,
    reversal_transaction_id,
    reversal_reason,
    reissued_from_payment_request_id,
    replacement_payment_request_id,
    reissue_reason,
    reissued_at
  )
  values (
    v_original.source_type,
    v_original.source_id,
    v_original.request_month,
    v_original.payee_type,
    v_original.payee_id,
    v_original.payee_name,
    v_original.business_entity_id,
    v_original.business_name,
    v_original.currency,
    v_original.amount,
    v_original.amount_jpy,
    v_original.amount_cny,
    'pending',
    v_original.due_date,
    null,
    v_note,
    v_reissued_at,
    v_reissued_at,
    null,
    null,
    null,
    null,
    null,
    null,
    v_original.id,
    null,
    nullif(trim(coalesce(p_reason, '')), ''),
    v_reissued_at
  )
  returning id into v_new_id;

  update public.school_payment_requests
  set
    replacement_payment_request_id = v_new_id,
    updated_at = v_reissued_at
  where id = v_original.id;

  return query
  select
    v_original.id,
    v_new_id,
    v_original.status,
    'pending'::text,
    v_reissued_at;
end;
$$;

revoke all on function public.school_reissue_reversed_payment_request(uuid,text)
  from public, anon, authenticated, service_role;
grant execute on function public.school_reissue_reversed_payment_request(uuid,text)
  to authenticated;

-- 手动测试 SQL（请在 Supabase SQL Editor 中按需替换 UUID 后执行；本文件不自动执行测试）

-- 1. 找一条 reversed payment request。
-- select
--   id,
--   source_type,
--   source_id,
--   request_month,
--   payee_name,
--   currency,
--   amount,
--   status,
--   replacement_payment_request_id
-- from public.school_payment_requests
-- where status = 'reversed'
-- order by reversed_at desc nulls last, updated_at desc
-- limit 10;

-- 2. 记录执行前的 expense / transaction / account 状态。
-- select count(*) as expense_count_before from public.school_expense_records;
-- select count(*) as transaction_count_before from public.school_account_transactions;
-- select id, current_balance from public.school_accounts order by name;

-- 3. 调用 reissue RPC。
-- select *
-- from public.school_reissue_reversed_payment_request(
--   'PAYMENT_REQUEST_UUID_HERE',
--   'test reissue'
-- );

-- 4. 确认生成新 pending。
-- select
--   id,
--   status,
--   reissued_from_payment_request_id,
--   replacement_payment_request_id,
--   paid_at,
--   paid_expense_id,
--   paid_account_transaction_id,
--   account_id,
--   reversed_at,
--   reversal_transaction_id,
--   reversal_reason,
--   reissue_reason,
--   reissued_at,
--   note
-- from public.school_payment_requests
-- where id in (
--   'PAYMENT_REQUEST_UUID_HERE',
--   (
--     select replacement_payment_request_id
--     from public.school_payment_requests
--     where id = 'PAYMENT_REQUEST_UUID_HERE'
--   )
-- )
-- order by created_at;

-- 5. 确认原 reversed 的 replacement_payment_request_id 写入。
-- select id, status, replacement_payment_request_id
-- from public.school_payment_requests
-- where id = 'PAYMENT_REQUEST_UUID_HERE';

-- 6. 确认新 pending 的 reissued_from_payment_request_id 写入。
-- select id, status, reissued_from_payment_request_id
-- from public.school_payment_requests
-- where reissued_from_payment_request_id = 'PAYMENT_REQUEST_UUID_HERE';

-- 7. 确认重复调用会失败。
-- select *
-- from public.school_reissue_reversed_payment_request(
--   'PAYMENT_REQUEST_UUID_HERE',
--   'duplicate test'
-- );

-- 8. 确认 paid / pending / cancelled / void 调用会失败。
-- select id, status
-- from public.school_payment_requests
-- where status in ('paid', 'pending', 'cancelled', 'void')
-- order by updated_at desc
-- limit 20;
--
-- select *
-- from public.school_reissue_reversed_payment_request(
--   'NON_REVERSED_PAYMENT_REQUEST_UUID_HERE',
--   'status guard test'
-- );

-- 9. 确认没有新增 expense。
-- select count(*) as expense_count_after from public.school_expense_records;

-- 10. 确认没有新增 account transaction。
-- select count(*) as transaction_count_after from public.school_account_transactions;

-- 11. 确认 account current_balance 没变。
-- select id, current_balance from public.school_accounts order by name;

-- 12. 确认 teacher wage lock 仍是 locked（请替换为真实锁定表字段后执行）。
-- select *
-- from public.school_teacher_wage_locks
-- where id = (
--   select source_id
--   from public.school_payment_requests
--   where id = 'PAYMENT_REQUEST_UUID_HERE'
-- )
-- limit 1;
