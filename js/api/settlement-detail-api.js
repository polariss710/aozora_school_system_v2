import { supabase } from "../supabase-client.js";

const SETTLEMENT_COLUMNS = [
  "id",
  "student_id",
  "year_month",
  "business_entity_id",
  "preset_exchange_rate",
  "planned_lesson_fee_jpy",
  "planned_lesson_fee_cny",
  "actual_lesson_fee_jpy",
  "actual_lesson_fee_cny",
  "previous_balance_cny",
  "received_jpy",
  "received_cny",
  "received_equivalent_cny",
  "system_difference_cny",
  "adjustment_amount_cny",
  "adjustment_reason",
  "carryover_amount_cny",
  "settlement_status",
  "locked_at",
  "unlocked_at",
  "unlock_reason",
  "note",
  "created_at",
  "updated_at",
].join(",");

const LESSON_COLUMNS = [
  "id",
  "lesson_type",
  "lesson_date",
  "year_month",
  "student_id",
  "teacher_id",
  "subject_id",
  "business_entity_id",
  "start_time",
  "end_time",
  "duration_hours",
  "lesson_content",
  "status",
  "is_billable",
  "note",
  "unit_price",
  "lesson_fee",
  "planned_lesson_id",
  "actual_minutes",
  "lesson_count",
  "teacher_settlement_month",
  "app_type",
  "created_at",
  "updated_at",
].join(",");

const INCOME_COLUMNS = [
  "id",
  "business_entity_id",
  "student_id",
  "student_payment_id",
  "account_id",
  "income_date",
  "year_month",
  "income_category",
  "description",
  "currency",
  "amount",
  "amount_jpy",
  "amount_cny",
  "exchange_rate",
  "payment_method",
  "status",
  "is_taxable_income",
  "tax_category",
  "receipt_status",
  "note",
  "app_type",
  "created_at",
  "updated_at",
  "settlement_month",
  "payment_currency",
  "include_in_student_settlement",
].join(",");

const ADJUSTMENT_COLUMNS = [
  "id",
  "settlement_id",
  "student_id",
  "year_month",
  "business_entity_id",
  "adjustment_amount_cny",
  "adjustment_source",
  "adjustment_reason",
  "note",
  "status",
  "created_by",
  "created_at",
  "updated_at",
].join(",");

export async function fetchSettlementDetailPage(settlementId) {
  const settlement = await fetchSettlement(settlementId);

  const [lookups, lessons, incomes, adjustments] = await Promise.all([
    fetchSettlementDetailLookups(),
    fetchLessonReferences(settlement),
    fetchIncomeReferences(settlement),
    fetchAdjustmentReferences(settlement.id),
  ]);

  return {
    settlement,
    lookups,
    lessons,
    incomes,
    adjustments,
  };
}

async function fetchSettlement(settlementId) {
  const { data, error } = await supabase
    .from("school_student_monthly_settlements")
    .select(SETTLEMENT_COLUMNS)
    .eq("id", settlementId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new Error("没有找到对应的学生月度结算记录。");
  }

  return data;
}

async function fetchLessonReferences(settlement) {
  const { data, error } = await supabase
    .from("school_lesson_records")
    .select(LESSON_COLUMNS)
    .eq("app_type", "school")
    .eq("student_id", settlement.student_id)
    .eq("year_month", settlement.year_month)
    .eq("business_entity_id", settlement.business_entity_id)
    .order("lesson_date", { ascending: true })
    .order("start_time", { ascending: true })
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchIncomeReferences(settlement) {
  const { data, error } = await supabase
    .from("school_income_records")
    .select(INCOME_COLUMNS)
    .eq("app_type", "school")
    .eq("student_id", settlement.student_id)
    .eq("settlement_month", settlement.year_month)
    .eq("business_entity_id", settlement.business_entity_id)
    .eq("include_in_student_settlement", true)
    .order("income_date", { ascending: true })
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchAdjustmentReferences(settlementId) {
  const { data, error } = await supabase
    .from("school_student_settlement_adjustments")
    .select(ADJUSTMENT_COLUMNS)
    .eq("settlement_id", settlementId)
    .order("created_at", { ascending: true })
    .order("id", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchSettlementDetailLookups() {
  const [studentsResult, businessEntitiesResult, teachersResult, subjectsResult, accountsResult] =
    await Promise.all([
      supabase
        .from("school_students")
        .select("id,student_code,name,display_name,status,course_track,target_type,default_currency,app_type")
        .eq("app_type", "school")
        .order("display_name", { ascending: true })
        .order("name", { ascending: true }),
      supabase
        .from("school_business_entities")
        .select("id,code,name,entity_type,default_currency,is_active")
        .order("name", { ascending: true }),
      supabase
        .from("school_teachers")
        .select("id,name,display_name,status,app_type")
        .eq("app_type", "school")
        .order("display_name", { ascending: true })
        .order("name", { ascending: true }),
      supabase
        .from("school_subjects")
        .select("id,name,category,primary_category,is_active")
        .order("sort_order", { ascending: true })
        .order("name", { ascending: true }),
      supabase
        .from("school_accounts")
        .select("id,account_code,name,currency,is_active,app_type")
        .eq("app_type", "school")
        .order("currency", { ascending: true })
        .order("name", { ascending: true }),
    ]);

  if (studentsResult.error) throw studentsResult.error;
  if (businessEntitiesResult.error) throw businessEntitiesResult.error;
  if (teachersResult.error) throw teachersResult.error;
  if (subjectsResult.error) throw subjectsResult.error;
  if (accountsResult.error) throw accountsResult.error;

  return {
    students: studentsResult.data || [],
    businessEntities: businessEntitiesResult.data || [],
    teachers: teachersResult.data || [],
    subjects: subjectsResult.data || [],
    accounts: accountsResult.data || [],
  };
}
