import { supabase } from "../supabase-client.js?v=v10-5-65-20260913-1";

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
