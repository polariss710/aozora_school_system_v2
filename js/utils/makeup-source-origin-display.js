const DISPLAY_KIND_CONFIG = Object.freeze({
  cancelled_original: Object.freeze({ prefix: "原定", showTime: true }),
  partial_planned_original: Object.freeze({ prefix: "原定", showTime: true }),
  partial_actual: Object.freeze({ prefix: "部分完成日", showTime: true }),
  week_fallback: Object.freeze({ prefix: "对应周", showTime: false }),
  ambiguous: Object.freeze({ prefix: "来源日期需核对", showTime: false }),
});

export function getMakeupSourceOriginDisplay(source = {}) {
  const kind = String(source.origin_display_kind || "").trim();
  const config = DISPLAY_KIND_CONFIG[kind] || DISPLAY_KIND_CONFIG.ambiguous;
  const selectable = kind !== "ambiguous"
    && Boolean(DISPLAY_KIND_CONFIG[kind])
    && source.origin_display_selectable !== false;

  return {
    kind: DISPLAY_KIND_CONFIG[kind] ? kind : "ambiguous",
    prefix: config.prefix,
    date: selectable ? source.origin_display_date || null : null,
    startTime: selectable && config.showTime
      ? source.origin_display_start_time || null
      : null,
    endTime: selectable && config.showTime
      ? source.origin_display_end_time || null
      : null,
    showTime: config.showTime,
    selectable,
  };
}

export function formatMakeupSourceOriginDisplay(
  originDisplay,
  { formatDate, formatTimeRange } = {}
) {
  if (!originDisplay?.selectable) {
    return originDisplay?.prefix || "来源日期需核对";
  }
  const dateText = typeof formatDate === "function"
    ? formatDate(originDisplay.date)
    : String(originDisplay.date || "");
  const values = [originDisplay.prefix, dateText];
  if (originDisplay.showTime) {
    const timeText = typeof formatTimeRange === "function"
      ? formatTimeRange(originDisplay.startTime, originDisplay.endTime)
      : [originDisplay.startTime, originDisplay.endTime].filter(Boolean).join(" - ");
    values.push(timeText);
  }
  return values.filter((value) => String(value || "").trim() && value !== "-").join(" ");
}
