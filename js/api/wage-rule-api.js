import { supabase } from "../supabase-client.js";
import { fetchCurrentStudentMonthCandidates } from "./student-status-api.js?v=phase-b4-remaining-20260807-1";

const WAGE_RULE_COLUMNS = [
  "id",
  "teacher_id",
  "student_id",
  "subject_id",
  "business_entity_id",
  "settlement_type",
  "hourly_rate_jpy",
  "hourly_rate_cny",
  "exchange_rate",
  "transport_fee_jpy",
  "classroom_fee_jpy",
  "is_active",
  "note",
  "created_at",
  "updated_at",
].join(",");

const TEACHER_COLUMNS = [
  "id",
  "name",
  "display_name",
  "teacher_code",
  "department",
  "status",
].join(",");

const SUBJECT_COLUMNS = [
  "id",
  "name",
  "category",
  "primary_category",
  "is_active",
].join(",");

const BUSINESS_ENTITY_COLUMNS = [
  "id",
  "name",
  "code",
  "entity_type",
  "is_active",
].join(",");

const RULE_AMOUNT_DEFAULT = 0;

export async function fetchWageRules() {
  const { data, error } = await supabase
    .from("school_teacher_wage_rules")
    .select(WAGE_RULE_COLUMNS)
    .order("created_at", { ascending: false });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchWageRuleDetailPage(wageRuleId) {
  const rule = await fetchWageRule(wageRuleId);

  const [teacher, studentCandidates, subject] = await Promise.all([
    fetchTeacher(rule.teacher_id),
    fetchCurrentStudentMonthCandidates({ selectedStudentId: rule.student_id }),
    fetchSubject(rule.subject_id),
  ]);

  return {
    rule,
    teacher,
    student: studentCandidates.find((row) => row.student_id === rule.student_id) || null,
    subject,
  };
}

export async function fetchWageRuleLookups(studentIds = []) {
  const ids = Array.from(new Set((studentIds || []).filter(Boolean)));
  const studentsRequest = ids.length
    ? supabase
      .from("school_students")
      .select("id,name,display_name,student_code")
      .eq("app_type", "school")
      .in("id", ids)
      .order("display_name", { ascending: true })
      .order("name", { ascending: true })
    : Promise.resolve({ data: [], error: null });
  const [teachersResult, studentsResult, subjectsResult, businessEntitiesResult] = await Promise.all([
    supabase
      .from("school_teachers")
      .select("id,name,display_name,department,status")
      .eq("app_type", "school")
      .order("display_name", { ascending: true })
      .order("name", { ascending: true }),
    studentsRequest,
    supabase
      .from("school_subjects")
      .select("id,name,category,primary_category,is_active")
      .order("sort_order", { ascending: true })
      .order("name", { ascending: true }),
    supabase
      .from("school_business_entities")
      .select("id,code,name,is_active")
      .order("name", { ascending: true }),
  ]);

  if (teachersResult.error) {
    throw teachersResult.error;
  }

  if (studentsResult.error) {
    throw studentsResult.error;
  }

  if (subjectsResult.error) {
    throw subjectsResult.error;
  }

  if (businessEntitiesResult.error) {
    throw businessEntitiesResult.error;
  }

  return {
    teachers: teachersResult.data || [],
    students: studentsResult.data || [],
    subjects: subjectsResult.data || [],
    businessEntities: businessEntitiesResult.data || [],
  };
}

export async function fetchWageRuleCurrentStudentCandidates({
  includeInactive = false,
  selectedStudentId = null,
} = {}) {
  return fetchCurrentStudentMonthCandidates({ includeInactive, selectedStudentId });
}

export async function createWageRuleConfig(payload) {
  const { data, error } = await supabase.rpc("school_create_teacher_wage_rule_config", {
    p_teacher_id: payload.teacherId,
    p_student_id: payload.studentId,
    p_subject_id: payload.subjectId,
    p_business_entity_id: payload.businessEntityId,
    p_settlement_type: payload.settlementType,
    p_hourly_rate_jpy: payload.hourlyRateJpy,
    p_hourly_rate_cny: payload.hourlyRateCny,
    p_exchange_rate: payload.exchangeRate ?? RULE_AMOUNT_DEFAULT,
    p_transport_fee_jpy: payload.transportFeeJpy ?? RULE_AMOUNT_DEFAULT,
    p_classroom_fee_jpy: payload.classroomFeeJpy ?? RULE_AMOUNT_DEFAULT,
    p_is_active: payload.isActive,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("老师工资规则新增失败：RPC 没有返回结果。");
  }

  return result;
}

export async function updateWageRuleConfig(payload) {
  const { data, error } = await supabase.rpc("school_update_teacher_wage_rule_config", {
    p_wage_rule_id: payload.wageRuleId,
    p_teacher_id: payload.teacherId,
    p_student_id: payload.studentId,
    p_subject_id: payload.subjectId,
    p_business_entity_id: payload.businessEntityId,
    p_settlement_type: payload.settlementType,
    p_hourly_rate_jpy: payload.hourlyRateJpy,
    p_hourly_rate_cny: payload.hourlyRateCny,
    p_exchange_rate: payload.exchangeRate,
    p_transport_fee_jpy: payload.transportFeeJpy,
    p_classroom_fee_jpy: payload.classroomFeeJpy,
    p_is_active: payload.isActive,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("老师工资规则配置更新失败：RPC 没有返回结果。");
  }

  return result;
}

export async function setWageRuleActiveState(payload) {
  const { data, error } = await supabase.rpc("school_set_teacher_wage_rule_active_state", {
    p_wage_rule_id: payload.wageRuleId,
    p_is_active: payload.isActive,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("老师工资规则状态更新失败：RPC 没有返回结果。");
  }

  return result;
}

async function fetchWageRule(wageRuleId) {
  const { data, error } = await supabase
    .from("school_teacher_wage_rules")
    .select(WAGE_RULE_COLUMNS)
    .eq("id", wageRuleId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new Error("没有找到对应的老师工资规则。");
  }

  return data;
}

async function fetchTeacher(teacherId) {
  if (!teacherId) return null;

  const { data, error } = await supabase
    .from("school_teachers")
    .select(TEACHER_COLUMNS)
    .eq("id", teacherId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  return data || null;
}

async function fetchSubject(subjectId) {
  if (!subjectId) return null;

  const { data, error } = await supabase
    .from("school_subjects")
    .select(SUBJECT_COLUMNS)
    .eq("id", subjectId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  return data || null;
}
