const YEAR_MONTH_PATTERN = /^\d{4}-(0[1-9]|1[0-2])$/;

export function isValidPartTimeWorkYearMonth(value) {
  return YEAR_MONTH_PATTERN.test(String(value || ""));
}

export function normalizePartTimeWorkFilters(filters, defaultYearMonth, workplaceOptions = []) {
  const yearMonth = isValidPartTimeWorkYearMonth(filters?.yearMonth)
    ? String(filters.yearMonth)
    : String(defaultYearMonth || "");
  const workplaceName = String(filters?.workplaceName || "").trim();
  const normalizedWorkplace = workplaceOptions.includes(workplaceName) ? workplaceName : "";
  const classDescription = normalizedWorkplace
    ? String(filters?.classDescription || "").trim()
    : "";

  return { yearMonth, workplaceName: normalizedWorkplace, classDescription };
}

export function partTimeWorkFiltersFromUrl(search, defaultYearMonth, workplaceOptions = []) {
  const params = new URLSearchParams(String(search || ""));
  const year = String(params.get("year") || "").trim();
  const month = String(params.get("month") || "").trim().padStart(2, "0");
  return normalizePartTimeWorkFilters({
    yearMonth: `${year}-${month}`,
    workplaceName: params.get("workplace_name"),
    classDescription: params.get("class_description"),
  }, defaultYearMonth, workplaceOptions);
}

export function buildPartTimeWorkFiltersUrl(href, filters) {
  const url = new URL(href);
  const [year, month] = String(filters.yearMonth || "").split("-");
  if (!isValidPartTimeWorkYearMonth(filters.yearMonth)) {
    throw new Error("PTW_FILTER_YEAR_MONTH_INVALID");
  }

  url.searchParams.set("year", year);
  url.searchParams.set("month", month);
  if (filters.workplaceName) {
    url.searchParams.set("workplace_name", filters.workplaceName);
  } else {
    url.searchParams.delete("workplace_name");
  }
  if (filters.workplaceName && filters.classDescription) {
    url.searchParams.set("class_description", filters.classDescription);
  } else {
    url.searchParams.delete("class_description");
  }
  return url;
}

export function resolvePartTimeWorkSettlementYearMonth({
  readerYearMonth,
  renderedYearMonth,
  appliedYearMonth,
}) {
  const readerValue = String(readerYearMonth || "");
  const renderedValue = String(renderedYearMonth || "");
  const appliedValue = String(appliedYearMonth || "");
  if (!isValidPartTimeWorkYearMonth(readerValue)
      || !isValidPartTimeWorkYearMonth(renderedValue)
      || !isValidPartTimeWorkYearMonth(appliedValue)
      || readerValue !== renderedValue
      || readerValue !== appliedValue) {
    throw new Error("PTW_SETTLEMENT_YEAR_MONTH_UNSAFE");
  }
  return readerValue;
}
