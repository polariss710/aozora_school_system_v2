import { supabase } from "../supabase-client.js";

const SETTLEMENT_COLUMNS = [
  "id",
  "student_id",
  "year_month",
  "business_entity_id",
  "preset_exchange_rate",
  "source_treatment_mode",
  "settlement_exchange_rate",
  "settlement_exchange_rate_source",
  "settlement_exchange_rate_effective_date",
  "lesson_variance_calculation_version",
  "unused_planned_credit_jpy",
  "unused_planned_credit_cny",
  "pending_makeup_hours",
  "lesson_variance_display_hours",
  "net_lesson_variance_jpy",
  "net_lesson_variance_cny",
  "lesson_variance_source_count",
  "lesson_variance_manifest_sha256",
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
  "duration_overage_minutes",
  "duration_overage_fee_jpy",
  "duration_overage_fee_cny",
  "duration_overage_actual_count",
  "duration_overage_policy_version",
  "duration_overage_source",
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
  "billing_month",
  "student_settlement_month",
  "teacher_settlement_month",
  "student_duration_overage_minutes",
  "student_duration_overage_fee_jpy",
  "student_duration_overage_policy_version",
  "student_duration_overage_source",
  "student_duration_overage_decided_at",
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
  const physicalSettlement = await fetchSettlement(settlementId);

  const [effectiveState, lookups, lessons, incomes, adjustments, wageBlockers] = await Promise.all([
    fetchSettlementEffectiveState(physicalSettlement.id),
    fetchSettlementDetailLookups(),
    fetchLessonReferences(physicalSettlement),
    fetchIncomeReferences(physicalSettlement),
    fetchAdjustmentReferences(physicalSettlement.id),
    fetchStudentSettlementWageBlockers(physicalSettlement.year_month, physicalSettlement.student_id),
  ]);
  const settlement = { ...physicalSettlement, ...effectiveState };

  return {
    settlement: mergeWageBlocker(settlement, wageBlockers[0]),
    lookups,
    lessons,
    incomes,
    adjustments,
  };
}

async function fetchSettlementEffectiveState(settlementId) {
  const { data, error } = await supabase.rpc(
    "school_get_student_monthly_settlement_effective_states",
    { p_settlement_ids: [settlementId] }
  );
  if (error) {
    throw error;
  }
  return (data || [])[0] || {};
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
    .rpc("school_list_lesson_management_records_authoritative", {
      p_year_month: settlement.year_month,
      p_week_start: null,
    })
    .eq("student_id", settlement.student_id)
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
    .from("school_operational_income_records")
    .select(INCOME_COLUMNS)
    .eq("app_type", "school")
    .eq("student_id", settlement.student_id)
    .eq("settlement_month", settlement.year_month)
    .eq("business_entity_id", settlement.business_entity_id)
    .eq("include_in_student_settlement", true)
    .eq("status", "received")
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

async function fetchStudentSettlementWageBlockers(yearMonth, studentId) {
  const { data, error } = await supabase.rpc("school_get_student_monthly_settlement_wage_blockers", {
    p_year_month: yearMonth,
    p_student_id: studentId,
  });

  if (error) {
    throw error;
  }

  return data || [];
}

function mergeWageBlocker(settlement, blocker) {
  if (!blocker) {
    return {
      ...settlement,
      teacher_wage_blocker_level: "",
      teacher_wage_blocker_reason: "",
      teacher_wage_blocker_counts: null,
    };
  }

  return {
    ...settlement,
    teacher_wage_blocker_level: blocker.blocker_level || "",
    teacher_wage_blocker_reason: blocker.blocker_reason || "",
    teacher_wage_blocker_counts: {
      activeWageLockCount: blocker.active_wage_lock_count || 0,
      wageDetailCount: blocker.wage_detail_count || 0,
      paymentRequestCount: blocker.payment_request_count || 0,
      paidPaymentRequestCount: blocker.paid_payment_request_count || 0,
      expenseCount: blocker.expense_count || 0,
      accountTransactionCount: blocker.account_transaction_count || 0,
      businessNames: blocker.wage_business_names || "",
    },
  };
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
