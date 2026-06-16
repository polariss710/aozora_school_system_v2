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

export function currentJapanDate() {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Tokyo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

export function monthFromUrl(search = window.location.search) {
  const params = new URLSearchParams(search);
  const year = String(params.get("year") || "").trim();
  const month = String(params.get("month") || "").trim().padStart(2, "0");
  const yearMonth = `${year}-${month}`;
  return /^\d{4}-(0[1-9]|1[0-2])$/.test(yearMonth) ? yearMonth : "";
}

export function initialYearMonthFromUrl() {
  return monthFromUrl() || currentYearMonth();
}

export function updateUrlMonthParams(yearMonth) {
  if (!window.history?.replaceState || !/^\d{4}-(0[1-9]|1[0-2])$/.test(String(yearMonth || ""))) {
    return;
  }

  const [year, month] = yearMonth.split("-");
  const url = new URL(window.location.href);
  url.searchParams.set("year", year);
  url.searchParams.set("month", month);
  window.history.replaceState({}, "", url);
}

export function buildMonthScopedHref(href, yearMonth) {
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(String(yearMonth || ""))) {
    return href;
  }

  const monthScopedPages = new Set([
    "income.html",
    "expense.html",
    "wage.html",
    "part-time-work.html",
  ]);
  const url = new URL(href, window.location.href);
  const pageName = url.pathname.split("/").pop();
  if (!monthScopedPages.has(pageName)) {
    return href;
  }

  const [year, month] = yearMonth.split("-");
  url.searchParams.set("year", year);
  url.searchParams.set("month", month);
  const query = url.searchParams.toString();
  return `./${pageName}${query ? `?${query}` : ""}${url.hash || ""}`;
}

export function updateMonthScopedNavigation(yearMonth, root = document) {
  root.querySelectorAll("nav.page-nav a[href]").forEach((link) => {
    const href = link.getAttribute("href");
    if (!href) {
      return;
    }
    link.setAttribute("href", buildMonthScopedHref(href, yearMonth));
  });
}
