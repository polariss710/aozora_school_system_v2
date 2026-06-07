import { supabase } from "../supabase-client.js";

const BUSINESS_ENTITY_COLUMNS = [
  "id",
  "code",
  "name",
  "entity_type",
  "default_currency",
  "is_company_report",
  "is_active",
  "note",
  "created_at",
  "updated_at",
].join(",");

export async function fetchBusinessEntities() {
  const { data, error } = await supabase
    .from("school_business_entities")
    .select(BUSINESS_ENTITY_COLUMNS)
    .order("name", { ascending: true })
    .order("code", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function createBusinessEntityProfile(payload) {
  const { data, error } = await supabase.rpc("school_create_business_entity_profile", {
    p_code: payload.code,
    p_name: payload.name,
    p_entity_type: payload.entityType,
    p_default_currency: payload.defaultCurrency,
    p_is_active: payload.isActive,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("业务归属新增失败：RPC 没有返回结果。");
  }

  return result;
}

export async function updateBusinessEntityProfile(payload) {
  const { data, error } = await supabase.rpc("school_update_business_entity_profile", {
    p_business_entity_id: payload.businessEntityId,
    p_name: payload.name,
    p_entity_type: payload.entityType,
    p_default_currency: payload.defaultCurrency,
    p_is_active: payload.isActive,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("业务归属基础信息更新失败：RPC 没有返回结果。");
  }

  return result;
}
