const REGUS_OFFICE_VENUE = "Regus办公室";

export function detectRegusOfficeConflictIds(rows) {
  const officeRows = (rows || []).filter((row) => String(row?.lesson_venue ?? "").trim() === REGUS_OFFICE_VENUE);
  return detectClassroomCapacityConflictIds(officeRows, 1);
}

export function detectClassroomCapacityConflictIds(rows, capacity = 2) {
  const ids = new Set();
  const normalizedCapacity = Number.isInteger(capacity) && capacity > 0 ? capacity : 2;
  const rowsByDate = new Map();

  for (const row of rows || []) {
    const start = timeMinutes(row?.start_time);
    const end = timeMinutes(row?.end_time);
    if (!row?.id || !row?.lesson_date || start === null || end === null || end <= start) continue;
    if (!rowsByDate.has(row.lesson_date)) rowsByDate.set(row.lesson_date, []);
    rowsByDate.get(row.lesson_date).push({ row, start, end });
  }

  for (const dateRows of rowsByDate.values()) {
    const boundaries = Array.from(new Set(dateRows.flatMap((item) => [item.start, item.end]))).sort((left, right) => left - right);
    for (let index = 0; index < boundaries.length - 1; index += 1) {
      const segmentStart = boundaries[index];
      const segmentEnd = boundaries[index + 1];
      if (segmentEnd <= segmentStart) continue;
      const activeRows = dateRows.filter((item) => item.start < segmentEnd && item.end > segmentStart);
      if (activeRows.length > normalizedCapacity) {
        activeRows.forEach((item) => ids.add(item.row.id));
      }
    }
  }

  return ids;
}

function timeMinutes(value) {
  const text = String(value ?? "").trim().slice(0, 5);
  if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(text)) return null;
  const [hour, minute] = text.split(":").map(Number);
  return hour * 60 + minute;
}
