import { supabase } from "../supabase-client.js";

const SUBJECT_COLUMNS = [
  "id",
  "name",
  "category",
  "color",
  "sort_order",
  "is_active",
  "note",
  "created_at",
  "updated_at",
  "primary_category",
  "tertiary_category",
].join(",");

export async function fetchSubjects() {
  const { data, error } = await supabase
    .from("school_subjects")
    .select(SUBJECT_COLUMNS)
    .order("sort_order", { ascending: true })
    .order("created_at", { ascending: true })
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function updateSubjectProfile(payload) {
  const { data, error } = await supabase.rpc("school_update_subject_profile", {
    p_subject_id: payload.subjectId,
    p_name: payload.name,
    p_status: payload.status,
    p_category: payload.category || null,
    p_primary_category: payload.primaryCategory || null,
    p_tertiary_category: payload.tertiaryCategory || null,
    p_color: payload.color || null,
    p_sort_order: payload.sortOrder,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("科目基础信息更新失败：RPC 没有返回结果。");
  }

  return result;
}

export async function createSubjectProfile(payload) {
  const { data, error } = await supabase.rpc("school_create_subject_profile", {
    p_name: payload.name,
    p_status: payload.status,
    p_category: payload.category || null,
    p_primary_category: payload.primaryCategory || null,
    p_tertiary_category: payload.tertiaryCategory || null,
    p_color: payload.color || null,
    p_sort_order: payload.sortOrder,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("科目新增失败：RPC 没有返回结果。");
  }

  return result;
}
