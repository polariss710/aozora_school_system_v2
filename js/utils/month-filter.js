export function populateYearSelect(select, range) {
  const currentYear = new Date().getFullYear();
  const startYear = Number(range.start);
  const endYear = Number(range.end);
  const years = new Set();

  for (let year = startYear; year <= endYear; year += 1) {
    years.add(year);
  }

  years.add(currentYear);

  select.innerHTML = Array.from(years)
    .sort((a, b) => a - b)
    .map((year) => `<option value="${year}">${year}年</option>`)
    .join("");
}

export function populateMonthSelect(select) {
  const options = [];

  for (let month = 1; month <= 12; month += 1) {
    const value = String(month).padStart(2, "0");
    options.push(`<option value="${value}">${value}月</option>`);
  }

  select.innerHTML = options.join("");
}

export function setYearMonthSelectValue(yearSelect, monthSelect, yearMonth) {
  const [year, month] = String(yearMonth || "").split("-");
  yearSelect.value = year || "";
  monthSelect.value = month || "";
}

export function getYearMonthSelectValue(yearSelect, monthSelect) {
  const year = yearSelect.value;
  const month = monthSelect.value;
  const yearMonth = `${year}-${month}`;

  if (!year || !month || !/^\d{4}-\d{2}$/.test(yearMonth)) {
    return "";
  }

  return yearMonth;
}

export function currentYearMonth() {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  return `${year}-${month}`;
}
