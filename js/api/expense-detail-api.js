import { supabase } from "../supabase-client.js?v=p1-b2b-auth-storage-20260810-1";
import { buildFunctionError } from "./function-error.js";
import { requireUuid } from "./validation.js";

const EXPENSE_DETAIL_COLUMNS = [
  "id",
  "business_entity_id",
  "teacher_id",
  "student_id",
  "salary_payment_id",
  "account_id",
  "expense_date",
  "year_month",
  "expense_category",
  "description",
  "currency",
  "amount",
  "amount_jpy",
  "amount_cny",
  "exchange_rate",
  "payment_method",
  "status",
  "cancelled_at",
  "cancelled_reason",
  "cancelled_by",
  "reversed_at",
  "reversal_reason",
  "reversal_account_transaction_id",
  "is_business_expense",
  "tax_category",
  "receipt_status",
  "note",
  "app_type",
  "created_at",
  "updated_at",
  "reimbursement_status",
  "reimbursement_note",
  "source_type",
  "source_id",
  "cash_creation_event_id",
  "created_by_user_id",
  "payee_name_snapshot",
  "cash_request_id",
  "cash_request_event_id",
  "cash_request_attempt_no",
  "cash_request_status",
  "cash_transaction_id",
  "cash_requested_at",
  "cash_synced_at",
  "cash_error_message",
  "cash_payment_amount",
  "cash_payment_currency",
  "cash_payment_note",
].join(",");

const PAYMENT_REQUEST_COLUMNS = [
  "id",
  "status",
  "source_type",
  "source_id",
  "request_month",
  "payee_name",
  "amount",
  "currency",
  "paid_at",
  "paid_expense_id",
  "paid_account_transaction_id",
  "account_id",
  "reversed_at",
  "reversal_transaction_id",
  "reversal_reason",
  "reissued_from_payment_request_id",
  "replacement_payment_request_id",
  "reissue_reason",
  "reissued_at",
  "created_at",
  "updated_at",
].join(",");

const ACCOUNT_TRANSACTION_COLUMNS = [
  "id",
  "account_id",
  "business_entity_id",
  "transaction_date",
  "year_month",
  "transaction_type",
  "related_table",
  "related_id",
  "currency",
  "amount",
  "balance_after",
  "description",
  "note",
  "app_type",
  "created_at",
  "updated_at",
].join(",");

const REIMBURSEMENT_ITEM_COLUMNS = [
  "id",
  "reimbursement_id",
  "expense_id",
  "amount",
  "note",
  "app_type",
  "created_at",
  "updated_at",
].join(",");

const REIMBURSEMENT_COLUMNS = [
  "id",
  "reimbursement_date",
  "year_month",
  "business_entity_id",
  "from_account_id",
  "to_account_id",
  "amount",
  "currency",
  "status",
  "note",
  "app_type",
  "created_at",
  "updated_at",
].join(",");

const ATTACHMENT_COLUMNS = [
  "id",
  "expense_id",
  "file_name",
  "file_type",
  "file_size",
  "source_type",
  "note",
  "app_type",
  "created_at",
  "updated_at",
].join(",");

export async function fetchExpenseDetailPage(expenseId) {
  const expense = await fetchExpenseDetail(expenseId);

  const [lookups, paymentRequests, directTransactions, reimbursementItems, attachments] =
    await Promise.all([
      fetchExpenseDetailLookups(expense),
      fetchPaymentRequestsByExpenseId(expense.id),
      fetchDirectAccountTransactions(expense.id),
      fetchReimbursementItems(expense.id),
      fetchExpenseAttachments(expense.id),
    ]);

  const paymentTransactionIds = transactionIdsFromPaymentRequests(paymentRequests);
  const [paymentTransactions, reimbursements] = await Promise.all([
    fetchAccountTransactionsByIds(paymentTransactionIds),
    fetchReimbursementsByIds(reimbursementItems.map((item) => item.reimbursement_id)),
  ]);

  return {
    expense,
    lookups,
    paymentRequests,
    directTransactions,
    paymentTransactions,
    reimbursementItems,
    reimbursements,
    attachments,
  };
}

export async function reverseExpenseRecord(payload) {
  const { data, error } = await supabase.rpc("school_reverse_expense_record", {
    p_expense_id: payload.expenseId,
    p_reversal_date: payload.reversalDate,
    p_reason: payload.reason || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("支出撤销失败。");
  }

  return result;
}

export async function voidUnsubmittedTeacherWageExpenseRecord(payload) {
  const expenseId = requireUuid(payload.expenseId, "expense_record_id");
  const { data, error } = await supabase.rpc("school_void_unsubmitted_teacher_wage_expense_record", {
    p_expense_record_id: expenseId,
    p_void_reason: payload.reason || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("老师工资支出记录作废失败。");
  }

  return result;
}

export async function updateExpenseRecord(payload) {
  const { data, error } = await supabase.rpc("school_update_expense_record", {
    p_expense_id: payload.expenseId,
    p_expected_updated_at: payload.expectedUpdatedAt,
    p_expense_date: payload.expenseDate,
    p_business_entity_id: payload.businessEntityId,
    p_account_id: payload.accountId,
    p_expense_category: payload.expenseCategory,
    p_description: payload.description,
    p_currency: payload.currency,
    p_amount: payload.amount,
    p_exchange_rate: payload.exchangeRate || null,
    p_payment_method: payload.paymentMethod || null,
    p_tax_category: payload.taxCategory || null,
    p_receipt_status: payload.receiptStatus || null,
    p_reimbursement_status: payload.reimbursementStatus || null,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("支出编辑失败。");
  }

  return result;
}

// 固定信用卡路线的可选卡列表。
//
// 放在本文件而不是 payment-api.js：后者被四个页面共用且全部不带缓存版本参数，
// 单独给它加会造成同一模块出现两个 URL、两份实例。卡列表只有支出详情页用得到，
// 归入本文件即可复用既有的版本链。
//
// 调的是 request-cash-expense-confirmation，与账户列表用的
// request-cash-confirmation 不同。后者是 legacy payment-request bridge，token
// 校验之后没有管理员限制；卡列表挂在 expense Edge 的管理员校验之后。
//
// 返回的卡可能带 cash_route_enabled: false（Cash 侧路线未启用）。这类卡仍会返回，
// 由调用方渲染成不可选状态——否则 Gate 未开时只能拿到空列表，无法区分「没有卡」
// 与「卡还没启用」。
//
// cash_route_enabled 为 true 也不代表这张卡当下可提交：还要过 School Gate、
// 卡币种与支出币种一致、卡归属一致等。它只能用来显示「Cash 侧未启用」这一种原因。
export async function fetchSchoolFixedRouteCardsViaFunction() {
  const { data, error } = await supabase.functions.invoke("request-cash-expense-confirmation", {
    body: {
      action: "list_fixed_route_cards",
    },
  });

  if (error) {
    throw error;
  }

  if (!data) {
    throw new Error("Cash System 可选信用卡读取失败：Function 没有返回结果。");
  }

  if (data.ok === false) {
    throw new Error(data.details || data.message || "Cash System 可选信用卡读取失败。");
  }

  return data.cards || [];
}

// 预览目标固定月与扣款日。只读，不创建任何请求或 attempt。
//
// 推导规则（cutoff / funding）在 Cash 侧，刷卡日落在 cutoff 前后会差整整一个月。
// 不在前端自行计算——那会把同一套规则实现两遍，前端那份迟早偏离。本入口与提交
// 路径共用同一个 Cash 函数，因此预览与实际落库的结果必然一致。
export async function fetchFixedCardSchedulePreview(payload) {
  const { data, error } = await supabase.functions.invoke("request-cash-expense-confirmation", {
    body: {
      action: "preview_fixed_card_schedule",
      card_instrument_id: payload.cardInstrumentId,
      charge_date: payload.chargeDate,
    },
  });

  if (error) {
    throw error;
  }

  if (!data) {
    throw new Error("固定月预览失败：Function 没有返回结果。");
  }

  if (data.ok === false) {
    throw new Error(data.details || data.message || "固定月预览失败。");
  }

  return data;
}

export async function requestCashExpenseConfirmation(payload) {
  const expenseId = requireUuid(payload.expenseId, "expense_record_id");

  // 两条支付路线的 payload 结构不同。
  //
  // 固定信用卡路线不传金额与币种：Edge 侧的 prepare RPC
  // school_request_cash_fixed_expense_payment_confirmation_v2 不接受金额参数，
  // 金额取自支出记录本身，币种由卡的 settlement_currency 决定。也不传账户——
  // 这条路线不经过任何 Cash 账户，而是在 Cash 生成一条固定项。
  //
  // charge_date 是刷卡日。Cash 侧据此按卡的 cutoff / funding 推导目标固定月与
  // 扣款日，前端不参与任何日期计算，也无法干预结果。
  const body = payload.paymentRoute === "fixed_credit_card"
    ? {
        expense_record_id: expenseId,
        payment_route: "fixed_credit_card",
        card_instrument_id: payload.cardInstrumentId,
        charge_date: payload.chargeDate,
        note: payload.note || null,
      }
    : {
        expense_record_id: expenseId,
        cash_account_id: payload.cashAccountId,
        actual_payment_amount: payload.actualPaymentAmount,
        actual_payment_currency: payload.actualPaymentCurrency,
        actual_payment_date: payload.actualPaymentDate,
        note: payload.note || null,
      };

  const { data, error } = await supabase.functions.invoke("request-cash-expense-confirmation", {
    body,
  });

  if (error) {
    throw await buildFunctionError(error, data, "Cash System 支出确认请求提交失败。");
  }

  if (!data) {
    throw new Error("Cash System 支出确认请求提交失败：Function 没有返回结果。");
  }

  if (data.ok === false) {
    throw new Error(data.details || data.message || "Cash System 支出确认请求提交失败。");
  }

  if (data.cash_request_status !== "pending") {
    throw new Error("Cash System 支出确认请求未停留在待确认状态。");
  }

  return data;
}

async function fetchExpenseDetail(expenseId) {
  const { data, error } = await supabase
    .from("school_expense_records")
    .select(EXPENSE_DETAIL_COLUMNS)
    .eq("app_type", "school")
    .eq("id", expenseId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new Error("没有找到对应的支出记录。");
  }

  return data;
}

async function fetchExpenseDetailLookups(expense) {
  const [businessEntitiesResult, accountsResult, teachersResult, studentsResult] = await Promise.all([
    supabase
      .from("school_business_entities")
      .select("id,name,is_active")
      .order("name", { ascending: true }),
    supabase
      .from("school_accounts")
      .select("id,account_code,name,currency,business_entity_id,current_balance,is_company_account,is_active,app_type")
      .eq("app_type", "school")
      .order("currency", { ascending: true })
      .order("name", { ascending: true }),
    supabase
      .from("school_teachers")
      .select("id,name,display_name,status,default_business_entity_id")
      .eq("app_type", "school")
      .order("display_name", { ascending: true })
      .order("name", { ascending: true }),
    supabase
      .from("school_students")
      .select("id,name,display_name,student_code,status,business_entity_id")
      .eq("app_type", "school")
      .eq("id", expense.student_id || "00000000-0000-0000-0000-000000000000"),
  ]);

  if (businessEntitiesResult.error) throw businessEntitiesResult.error;
  if (accountsResult.error) throw accountsResult.error;
  if (teachersResult.error) throw teachersResult.error;
  if (studentsResult.error) throw studentsResult.error;

  return {
    businessEntities: businessEntitiesResult.data || [],
    accounts: accountsResult.data || [],
    teachers: teachersResult.data || [],
    students: studentsResult.data || [],
  };
}

async function fetchPaymentRequestsByExpenseId(expenseId) {
  const { data, error } = await supabase
    .from("school_payment_requests")
    .select(PAYMENT_REQUEST_COLUMNS)
    .eq("source_type", "teacher_wage")
    .eq("paid_expense_id", expenseId)
    .order("created_at", { ascending: false });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchDirectAccountTransactions(expenseId) {
  const { data, error } = await supabase
    .from("school_account_transactions")
    .select(ACCOUNT_TRANSACTION_COLUMNS)
    .eq("app_type", "school")
    .eq("related_table", "school_expense_records")
    .eq("related_id", expenseId)
    .order("transaction_date", { ascending: true })
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchAccountTransactionsByIds(ids) {
  const transactionIds = Array.from(new Set((ids || []).filter(Boolean)));
  if (!transactionIds.length) {
    return [];
  }

  const { data, error } = await supabase
    .from("school_account_transactions")
    .select(ACCOUNT_TRANSACTION_COLUMNS)
    .eq("app_type", "school")
    .in("id", transactionIds)
    .order("transaction_date", { ascending: true })
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchReimbursementItems(expenseId) {
  const { data, error } = await supabase
    .from("school_reimbursement_items")
    .select(REIMBURSEMENT_ITEM_COLUMNS)
    .eq("app_type", "school")
    .eq("expense_id", expenseId)
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchReimbursementsByIds(ids) {
  const reimbursementIds = Array.from(new Set((ids || []).filter(Boolean)));
  if (!reimbursementIds.length) {
    return [];
  }

  const { data, error } = await supabase
    .from("school_reimbursements")
    .select(REIMBURSEMENT_COLUMNS)
    .eq("app_type", "school")
    .in("id", reimbursementIds)
    .order("reimbursement_date", { ascending: true })
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchExpenseAttachments(expenseId) {
  const { data, error } = await supabase
    .from("school_expense_attachments")
    .select(ATTACHMENT_COLUMNS)
    .eq("app_type", "school")
    .eq("expense_id", expenseId)
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

function transactionIdsFromPaymentRequests(paymentRequests) {
  return paymentRequests.flatMap((request) => [
    request.paid_account_transaction_id,
    request.reversal_transaction_id,
  ]);
}
