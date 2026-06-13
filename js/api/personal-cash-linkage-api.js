import { supabase } from "../supabase-client.js?v=v2.111.0-supabase-auth-client-init-20260614";

export async function listPersonalCashAccountMappings(filters = {}) {
  const { data, error } = await supabase.rpc("school_list_personal_cash_account_mappings", {
    p_business_entity_id: filters.businessEntityId || null,
    p_include_inactive: Boolean(filters.includeInactive),
  });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function createPersonalCashAccountMapping(payload) {
  const { data, error } = await supabase.rpc("school_create_personal_cash_account_mapping", {
    p_business_entity_id: payload.businessEntityId,
    p_cash_user_id: payload.cashUserId,
    p_cash_account_id: payload.cashAccountId,
    p_cash_account_name_snapshot: payload.cashAccountNameSnapshot,
    p_cash_account_type_snapshot: payload.cashAccountTypeSnapshot,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("个人业务 Cash 账户映射新增失败：RPC 没有返回结果。");
  }

  return result;
}

export async function updatePersonalCashAccountMapping(payload) {
  const { data, error } = await supabase.rpc("school_update_personal_cash_account_mapping", {
    p_mapping_id: payload.mappingId,
    p_cash_account_name_snapshot: payload.cashAccountNameSnapshot ?? null,
    p_cash_account_type_snapshot: payload.cashAccountTypeSnapshot ?? null,
    p_is_active: typeof payload.isActive === "boolean" ? payload.isActive : null,
    p_note: payload.note ?? null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("个人业务 Cash 账户映射更新失败：RPC 没有返回结果。");
  }

  return result;
}

export async function createPersonalCashLinkageEvent(payload) {
  const { data, error } = await supabase.rpc("school_create_personal_cash_linkage_event", {
    p_payment_request_id: payload.paymentRequestId,
    p_cash_account_mapping_id: payload.cashAccountMappingId,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("个人业务 Cash 联动事件创建失败：RPC 没有返回结果。");
  }

  return result;
}

export async function fetchPersonalCashLinkageEvents(filters = {}) {
  const { data, error } = await supabase.rpc("school_get_personal_cash_linkage_events", {
    p_payment_request_id: filters.paymentRequestId || null,
    p_sync_status: filters.syncStatus || null,
  });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function updatePersonalCashLinkageEventStatus(payload) {
  const { data, error } = await supabase.rpc(
    "school_update_personal_cash_linkage_event_status",
    {
      p_event_id: payload.eventId,
      p_sync_status: payload.syncStatus,
      p_cash_transaction_id: payload.cashTransactionId || null,
      p_last_error: payload.lastError || null,
    }
  );

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("个人业务 Cash 联动状态更新失败：RPC 没有返回结果。");
  }

  return result;
}
