import { supabase } from "../supabase-client.js";

export async function fetchStudentMonthCandidates({
  month,
  includeInactive = false,
  selectedStudentId = null,
}) {
  const normalizedMonth = String(month || "").trim();
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(normalizedMonth)) {
    throw new Error("请选择正确的学生状态月份。");
  }

  const { data, error } = await supabase.rpc("school_list_student_month_candidates_v1", {
    p_target_month: `${normalizedMonth}-01`,
    p_include_inactive: Boolean(includeInactive),
    p_selected_student_id: selectedStudentId || null,
  });

  if (error) {
    throw error;
  }
  return data || [];
}
