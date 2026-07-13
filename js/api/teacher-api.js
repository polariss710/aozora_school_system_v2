import { supabase } from "../supabase-client.js";

const TEACHER_COLUMNS = [
  "id",
  "teacher_code",
  "name",
  "display_name",
  "department",
  "default_subject_id",
  "default_business_entity_id",
  "bank_name",
  "bank_branch_code",
  "bank_branch_name",
  "bank_account_number",
  "alipay_account",
  "wechat_account",
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
    .select("id,code,name,is_active")
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchSubjectsForTeachers() {
  const { data, error } = await supabase
    .from("school_subjects")
    .select("id,name,category,primary_category,tertiary_category,is_active,sort_order")
    .order("sort_order", { ascending: true, nullsFirst: false })
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function updateTeacherProfile(payload) {
  const { data, error } = await supabase.rpc("school_update_teacher_profile", {
    p_teacher_id: payload.teacherId,
    p_profile: {
      name: payload.name,
      department: payload.department,
      default_subject_id: payload.defaultSubjectId || null,
      default_business_entity_id: payload.defaultBusinessEntityId || null,
      status: payload.status,
      note: payload.note || null,
      alipay_account: payload.alipayAccount || null,
      wechat_account: payload.wechatAccount || null,
      bank_name: payload.bankName || null,
      bank_branch_code: payload.bankBranchCode || null,
      bank_branch_name: payload.bankBranchName || null,
      bank_account_number: payload.bankAccountNumber || null,
    },
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
    p_profile: {
      name: payload.name || null,
      department: payload.department || null,
      default_subject_id: payload.defaultSubjectId || null,
      default_business_entity_id: payload.defaultBusinessEntityId || null,
      status: payload.status,
      note: payload.note || null,
      alipay_account: payload.alipayAccount || null,
      wechat_account: payload.wechatAccount || null,
      bank_name: payload.bankName || null,
      bank_branch_code: payload.bankBranchCode || null,
      bank_branch_name: payload.bankBranchName || null,
      bank_account_number: payload.bankAccountNumber || null,
    },
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
