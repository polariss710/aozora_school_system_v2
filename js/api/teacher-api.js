import { supabase } from "../supabase-client.js";

const TEACHER_COLUMNS = [
  "id",
  "teacher_code",
  "name",
  "kana_name",
  "display_name",
  "department",
  "default_hourly_rate",
  "default_currency",
  "default_payment_currency",
  "default_business_entity_id",
  "default_payment_method",
  "status",
  "note",
  "app_type",
  "created_at",
  "updated_at",
].join(",");

export async function fetchTeachers(filters) {
  let query = supabase
    .from("school_teachers")
    .select(TEACHER_COLUMNS)
    .eq("app_type", "school")
    .order("display_name", { ascending: true })
    .order("name", { ascending: true });

  query = applyTeacherFilters(query, filters);

  const { data, error } = await query;
  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchTeacherFilterOptions() {
  const { data, error } = await supabase
    .from("school_teachers")
    .select("status,department,default_business_entity_id")
    .eq("app_type", "school");

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchBusinessEntitiesForTeachers() {
  const { data, error } = await supabase
    .from("school_business_entities")
    .select("id,name,is_active")
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function updateTeacherProfile(payload) {
  const { data, error } = await supabase.rpc("school_update_teacher_profile", {
    p_teacher_id: payload.teacherId,
    p_display_name: payload.displayName,
    p_status: payload.status,
    p_default_business_entity_id: payload.defaultBusinessEntityId || null,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("老师基础信息更新失败：RPC 没有返回结果。");
  }

  return result;
}

export async function createTeacherProfile(payload) {
  const { data, error } = await supabase.rpc("school_create_teacher_profile", {
    p_display_name: payload.displayName,
    p_teacher_code: payload.teacherCode || null,
    p_name: payload.name || null,
    p_kana_name: payload.kanaName || null,
    p_status: payload.status,
    p_department: payload.department || null,
    p_default_business_entity_id: payload.defaultBusinessEntityId || null,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("老师新增失败：RPC 没有返回结果。");
  }

  return result;
}

function applyTeacherFilters(query, filters) {
  if (filters.status) {
    query = query.eq("status", filters.status);
  }

  if (filters.department) {
    query = query.eq("department", filters.department);
  }

  if (filters.businessEntityId === "__unset__") {
    query = query.is("default_business_entity_id", null);
  } else if (filters.businessEntityId) {
    query = query.eq("default_business_entity_id", filters.businessEntityId);
  }

  return query;
}
