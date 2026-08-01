const AUTHORITATIVE_PLANNED_FEE_FIELDS = [
  "base_lesson_fee_jpy",
  "aircon_unit_price_jpy_snapshot",
  "aircon_billable_hours_snapshot",
  "aircon_fee_jpy",
  "lesson_total_fee_jpy",
];

export function hasAuthoritativePlannedFeeBundle(record) {
  return Boolean(
    record
    && record.lesson_type === "planned"
    && String(record.fee_calculation_version || "").trim()
    && AUTHORITATIVE_PLANNED_FEE_FIELDS.every((field) => (
      record[field] !== null
      && record[field] !== undefined
      && Number.isFinite(Number(record[field]))
    ))
  );
}

export function plannedAirconConditionLabel(record) {
  if (record?.aircon_charge_status === "calculated") {
    return "周末固定办公室计费";
  }
  if (record?.aircon_charge_status === "configured_zero") {
    return "符合空调计费条件，费率为0";
  }
  return "不符合当前空调计费条件";
}
