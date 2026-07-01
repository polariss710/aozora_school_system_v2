import { formatCurrency, formatMonth, safeText } from "./format.js";

const DUTY_REPORT_MIN_DETAIL_ROWS = 31;
const DUTY_REPORT_HEADERS = [
  "日期及星期",
  "学生",
  "课程 / 工作内容",
  "",
  "开始时间",
  "结束时间",
  "结算课时",
  "交通费 JPY",
  "教室费 JPY",
  "备注",
];
const ZIP_CRC32_TABLE = buildCrc32Table();

export function exportWageDutyReportXlsx(data) {
  const { wageLock } = data;
  const xlsx = window.XLSX;
  const workbook = xlsx.utils.book_new();

  appendWageDutyReportSheet(workbook, data, "勤务申报表");
  xlsx.writeFile(workbook, buildWageDutyReportFileName(wageLock), {
    bookType: "xlsx",
    cellStyles: true,
  });
}

export function exportBatchWageDutyReportXlsx(reports, { month }) {
  const xlsx = window.XLSX;
  const usedFileNames = new Set();
  const zipEntries = [];

  for (const reportData of reports) {
    const workbook = xlsx.utils.book_new();
    const fileName = uniqueFileName(buildBatchWageDutyReportEntryFileName(reportData.wageLock), usedFileNames);
    appendWageDutyReportSheet(workbook, reportData, "勤务申报表");
    zipEntries.push({
      name: fileName,
      data: normalizeZipEntryData(xlsx.write(workbook, {
        bookType: "xlsx",
        type: "array",
        cellStyles: true,
      })),
    });
  }

  downloadBlob(buildZipBlob(zipEntries), buildBatchWageDutyReportZipFileName(month));
}

function appendWageDutyReportSheet(workbook, data, sheetName) {
  const { wageLock, details } = data;
  const xlsx = window.XLSX;
  const report = buildWageDutyReport(wageLock, details || []);
  const sheet = xlsx.utils.aoa_to_sheet(report.rows);

  sheet["!cols"] = [
    { wch: 18 },
    { wch: 16 },
    { wch: 28 },
    { wch: 28 },
    { wch: 12 },
    { wch: 12 },
    { wch: 12 },
    { wch: 14 },
    { wch: 14 },
    { wch: 22 },
  ];
  sheet["!rows"] = report.rows.map((_, index) => ({
    hpt: index === 0 ? 28 : index === 2 ? 34 : 22,
  }));
  sheet["!merges"] = report.merges.map((range) => xlsx.utils.decode_range(range));

  styleWageDutyReportSheet(sheet, report);
  xlsx.utils.book_append_sheet(workbook, sheet, sheetName);
}

function buildWageDutyReport(wageLock, details) {
  const detailRowCount = Math.max(DUTY_REPORT_MIN_DETAIL_ROWS, details.length);
  const rows = [
    ["勤务申报表（讲师填写用）", "", "", "", "", "", "", "", "", ""],
    [
      "月份",
      japaneseMonthText(wageLock.settlement_month),
      "姓名",
      displayValue(wageLock.teacher_name),
      "",
      "",
      "支付方式",
      "日元银行 / 支付宝 / 微信",
      "",
      "",
    ],
    [
      "※ 本表用于老师确认工资快照明细并补充交通费、教室费、备注和支付信息。请勿修改系统已填写的日期、学生、课程、开始时间、结束时间和结算课时。",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
    ],
    DUTY_REPORT_HEADERS,
  ];

  for (let index = 0; index < detailRowCount; index += 1) {
    const detail = details[index] || null;
    rows.push(buildDutyDetailRow(detail));
  }

  const detailStartRow = 5;
  const detailEndRow = detailStartRow + detailRowCount - 1;
  const totalRowNumber = detailEndRow + 1;
  rows.push([
    "合计",
    "",
    "",
    "",
    "",
    "",
    { f: `SUM(G${detailStartRow}:G${detailEndRow})` },
    { f: `SUM(H${detailStartRow}:H${detailEndRow})` },
    { f: `SUM(I${detailStartRow}:I${detailEndRow})` },
    "",
  ]);

  rows.push([
    `系统快照合计：结算课时 ${displayValue(wageLock.pay_hours)} / 课时工资 ${formatCurrency(wageLock.lesson_wage_jpy, "JPY")} / 费用 ${formatCurrency(wageLock.fee_jpy, "JPY")} / 合计 ${formatCurrency(wageLock.total_jpy, "JPY")}`,
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
  ]);

  rows.push(["日元支付（银行振込）", "", "", "", "", "", "", "", "", ""]);
  rows.push(["銀行名", "支店番号", "支店名", "口座番号", "名義", "", "备注", "", "", ""]);
  rows.push(["", "", "", "", "", "", "", "", "", ""]);
  rows.push(["人民币支付", "", "", "", "", "", "", "", "", ""]);
  rows.push(["支付宝", "微信", "", "", "", "备注", "", "", "", ""]);
  rows.push(["", "", "", "", "", "", "", "", "", ""]);
  rows.push(["老师确认", "", "", "", "", "", "", "", "", ""]);
  rows.push(["确认日期", "", "老师签名", "", "", "备注", "", "", "", ""]);
  rows.push(["", "", "", "", "", "", "", "", "", ""]);

  const totalRowIndex = totalRowNumber - 1;
  const summaryRowIndex = totalRowIndex + 1;
  const bankTitleRowIndex = summaryRowIndex + 1;
  const bankHeaderRowIndex = bankTitleRowIndex + 1;
  const bankInputRowIndex = bankHeaderRowIndex + 1;
  const cnyTitleRowIndex = bankInputRowIndex + 1;
  const cnyHeaderRowIndex = cnyTitleRowIndex + 1;
  const cnyInputRowIndex = cnyHeaderRowIndex + 1;
  const confirmTitleRowIndex = cnyInputRowIndex + 1;
  const confirmHeaderRowIndex = confirmTitleRowIndex + 1;
  const confirmInputRowIndex = confirmHeaderRowIndex + 1;

  return {
    rows,
    detailStartRow,
    detailEndRow,
    totalRowIndex,
    summaryRowIndex,
    bankTitleRowIndex,
    bankHeaderRowIndex,
    bankInputRowIndex,
    cnyTitleRowIndex,
    cnyHeaderRowIndex,
    cnyInputRowIndex,
    confirmTitleRowIndex,
    confirmHeaderRowIndex,
    confirmInputRowIndex,
    merges: [
      "A1:J1",
      "D2:F2",
      "H2:J2",
      "A3:J3",
      ...Array.from({ length: detailRowCount }, (_, index) => `C${detailStartRow + index}:D${detailStartRow + index}`),
      `A${totalRowNumber}:F${totalRowNumber}`,
      `A${totalRowNumber + 1}:J${totalRowNumber + 1}`,
      `A${totalRowNumber + 2}:J${totalRowNumber + 2}`,
      `E${totalRowNumber + 3}:F${totalRowNumber + 3}`,
      `G${totalRowNumber + 3}:J${totalRowNumber + 3}`,
      `E${totalRowNumber + 4}:F${totalRowNumber + 4}`,
      `G${totalRowNumber + 4}:J${totalRowNumber + 4}`,
      `A${totalRowNumber + 5}:J${totalRowNumber + 5}`,
      `B${totalRowNumber + 6}:E${totalRowNumber + 6}`,
      `F${totalRowNumber + 6}:J${totalRowNumber + 6}`,
      `B${totalRowNumber + 7}:E${totalRowNumber + 7}`,
      `F${totalRowNumber + 7}:J${totalRowNumber + 7}`,
      `A${totalRowNumber + 8}:J${totalRowNumber + 8}`,
      `C${totalRowNumber + 9}:E${totalRowNumber + 9}`,
      `F${totalRowNumber + 9}:J${totalRowNumber + 9}`,
      `C${totalRowNumber + 10}:E${totalRowNumber + 10}`,
      `F${totalRowNumber + 10}:J${totalRowNumber + 10}`,
    ],
  };
}

function buildDutyDetailRow(detail) {
  if (!detail) {
    return ["", "", "", "", "", "", 0, 0, 0, ""];
  }

  return [
    dutyDateText(detail.lesson_date),
    displayValue(detail.student_name),
    dutyWorkContent(detail),
    "",
    timeOnly(detail.start_time),
    timeOnly(detail.end_time),
    numberOrZero(detail.pay_hours),
    numberOrZero(detail.transport_fee_jpy),
    numberOrZero(detail.classroom_fee_jpy),
    "",
  ];
}

function styleWageDutyReportSheet(sheet, report) {
  const allRange = `A1:J${report.rows.length}`;
  const baseStyle = {
    font: { name: "Arial", sz: 10 },
    alignment: { vertical: "center", wrapText: true },
    border: {
      top: { style: "thin", color: { rgb: "D9D9D9" } },
      bottom: { style: "thin", color: { rgb: "D9D9D9" } },
      left: { style: "thin", color: { rgb: "D9D9D9" } },
      right: { style: "thin", color: { rgb: "D9D9D9" } },
    },
  };
  const labelStyle = {
    ...baseStyle,
    font: { name: "Arial", sz: 10, bold: true },
    fill: { fgColor: { rgb: "EAF2F8" } },
    alignment: { horizontal: "center", vertical: "center", wrapText: true },
  };
  const lockedStyle = {
    ...baseStyle,
    fill: { fgColor: { rgb: "F7F9FC" } },
  };
  const editableStyle = {
    ...baseStyle,
    fill: { fgColor: { rgb: "FFFCEB" } },
  };
  const totalStyle = {
    ...baseStyle,
    font: { name: "Arial", sz: 10, bold: true },
    fill: { fgColor: { rgb: "E2F0D9" } },
    alignment: { horizontal: "center", vertical: "center", wrapText: true },
  };
  const sectionStyle = {
    ...baseStyle,
    font: { name: "Arial", sz: 11, bold: true },
    fill: { fgColor: { rgb: "D9EAD3" } },
    alignment: { horizontal: "left", vertical: "center", wrapText: true },
  };

  applyCellStyle(sheet, allRange, baseStyle);
  applyCellStyle(sheet, "A1:J1", {
    ...baseStyle,
    font: { name: "Arial", sz: 16, bold: true },
    alignment: { horizontal: "center", vertical: "center" },
    fill: { fgColor: { rgb: "D9EAF7" } },
  });
  applyCellStyle(sheet, "A2:A2", labelStyle);
  applyCellStyle(sheet, "C2:C2", labelStyle);
  applyCellStyle(sheet, "G2:G2", labelStyle);
  applyCellStyle(sheet, "B2:F2", lockedStyle);
  applyCellStyle(sheet, "H2:J2", editableStyle);
  applyCellStyle(sheet, "A3:J3", {
    ...baseStyle,
    fill: { fgColor: { rgb: "FFF2CC" } },
    alignment: { vertical: "center", wrapText: true },
  });
  applyCellStyle(sheet, "A4:J4", labelStyle);
  applyCellStyle(sheet, `A${report.detailStartRow}:G${report.detailEndRow}`, lockedStyle);
  applyCellStyle(sheet, `H${report.detailStartRow}:J${report.detailEndRow}`, editableStyle);
  applyCellStyle(sheet, `A${report.totalRowIndex + 1}:J${report.totalRowIndex + 1}`, totalStyle);
  applyCellStyle(sheet, `A${report.summaryRowIndex + 1}:J${report.summaryRowIndex + 1}`, {
    ...baseStyle,
    font: { name: "Arial", sz: 10, bold: true },
    fill: { fgColor: { rgb: "F3F6FA" } },
  });

  for (const rowIndex of [report.bankTitleRowIndex, report.cnyTitleRowIndex, report.confirmTitleRowIndex]) {
    applyCellStyle(sheet, `A${rowIndex + 1}:J${rowIndex + 1}`, sectionStyle);
  }
  for (const rowIndex of [report.bankHeaderRowIndex, report.cnyHeaderRowIndex, report.confirmHeaderRowIndex]) {
    applyCellStyle(sheet, `A${rowIndex + 1}:J${rowIndex + 1}`, labelStyle);
  }
  for (const rowIndex of [report.bankInputRowIndex, report.cnyInputRowIndex, report.confirmInputRowIndex]) {
    applyCellStyle(sheet, `A${rowIndex + 1}:J${rowIndex + 1}`, editableStyle);
  }

  for (let row = report.detailStartRow; row <= report.detailEndRow; row += 1) {
    applyNumberFormat(sheet, `G${row}:G${row}`, "0.##");
    applyNumberFormat(sheet, `H${row}:I${row}`, "#,##0");
  }
  applyNumberFormat(sheet, `G${report.totalRowIndex + 1}:G${report.totalRowIndex + 1}`, "0.##");
  applyNumberFormat(sheet, `H${report.totalRowIndex + 1}:I${report.totalRowIndex + 1}`, "#,##0");
}

function applyCellStyle(sheet, range, style) {
  const decodedRange = window.XLSX.utils.decode_range(range);
  for (let row = decodedRange.s.r; row <= decodedRange.e.r; row += 1) {
    for (let column = decodedRange.s.c; column <= decodedRange.e.c; column += 1) {
      const address = window.XLSX.utils.encode_cell({ r: row, c: column });
      if (!sheet[address]) {
        sheet[address] = { t: "s", v: "" };
      }
      sheet[address].s = { ...(sheet[address].s || {}), ...style };
    }
  }
}

function applyNumberFormat(sheet, range, format) {
  const decodedRange = window.XLSX.utils.decode_range(range);
  for (let row = decodedRange.s.r; row <= decodedRange.e.r; row += 1) {
    for (let column = decodedRange.s.c; column <= decodedRange.e.c; column += 1) {
      const address = window.XLSX.utils.encode_cell({ r: row, c: column });
      if (sheet[address]) {
        sheet[address].z = format;
      }
    }
  }
}

function buildWageDutyReportFileName(wageLock) {
  const teacherName = sanitizeFileName(displayValue(wageLock.teacher_name)).replaceAll("-", "") || "teacher";
  const month = formatMonth(wageLock.settlement_month).replaceAll("/", "-");
  return `${teacherName}_${month}_勤务申报表.xlsx`;
}

function buildBatchWageDutyReportEntryFileName(wageLock) {
  const teacherName = sanitizeFileName(displayValue(wageLock.teacher_name)).replaceAll("-", "") || "teacher";
  const businessName = sanitizeFileName(displayValue(wageLock.business_name)).replaceAll("-", "") || "business";
  const month = formatMonth(wageLock.settlement_month).replaceAll("/", "-");
  return `${teacherName}_${businessName}_${month}_勤务申报表.xlsx`;
}

function buildBatchWageDutyReportZipFileName(month) {
  const normalizedMonth = formatMonth(month).replaceAll("/", "-") || "month";
  return `老师勤务申报表_${sanitizeFileName(normalizedMonth)}_批量.zip`;
}

function uniqueFileName(baseName, usedFileNames) {
  const dotIndex = baseName.lastIndexOf(".");
  const stem = dotIndex > 0 ? baseName.slice(0, dotIndex) : baseName;
  const extension = dotIndex > 0 ? baseName.slice(dotIndex) : "";
  const sanitizedStem = sanitizeFileName(stem) || "勤务申报表";
  let candidate = `${sanitizedStem}${extension}`;
  let suffix = 2;
  while (usedFileNames.has(candidate)) {
    const suffixText = `_${suffix}`;
    candidate = `${sanitizedStem}${suffixText}${extension}`;
    suffix += 1;
  }
  usedFileNames.add(candidate);
  return candidate;
}

function sanitizeFileName(value) {
  return safeText(value).replace(/[\\/:*?"<>|]/g, "-").trim();
}

function normalizeZipEntryData(value) {
  if (value instanceof Uint8Array) {
    return value;
  }
  if (value instanceof ArrayBuffer) {
    return new Uint8Array(value);
  }
  if (ArrayBuffer.isView(value)) {
    return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
  }
  throw new Error("Excel 导出数据格式不受支持。");
}

function buildZipBlob(entries) {
  const localParts = [];
  const centralParts = [];
  let offset = 0;
  const timestamp = zipDosTimestamp(new Date());

  for (const entry of entries) {
    const fileNameBytes = new TextEncoder().encode(entry.name);
    const crc = crc32(entry.data);
    const localHeader = buildZipLocalHeader({
      fileNameBytes,
      crc,
      size: entry.data.length,
      timestamp,
    });
    const centralHeader = buildZipCentralHeader({
      fileNameBytes,
      crc,
      size: entry.data.length,
      offset,
      timestamp,
    });
    localParts.push(localHeader, entry.data);
    centralParts.push(centralHeader);
    offset += localHeader.length + entry.data.length;
  }

  const centralOffset = offset;
  const centralSize = centralParts.reduce((total, part) => total + part.length, 0);
  const endRecord = buildZipEndRecord({
    entryCount: entries.length,
    centralSize,
    centralOffset,
  });

  return new Blob([...localParts, ...centralParts, endRecord], { type: "application/zip" });
}

function buildZipLocalHeader({ fileNameBytes, crc, size, timestamp }) {
  const header = new Uint8Array(30 + fileNameBytes.length);
  const view = new DataView(header.buffer);
  view.setUint32(0, 0x04034b50, true);
  view.setUint16(4, 20, true);
  view.setUint16(6, 0x0800, true);
  view.setUint16(8, 0, true);
  view.setUint16(10, timestamp.time, true);
  view.setUint16(12, timestamp.date, true);
  view.setUint32(14, crc, true);
  view.setUint32(18, size, true);
  view.setUint32(22, size, true);
  view.setUint16(26, fileNameBytes.length, true);
  view.setUint16(28, 0, true);
  header.set(fileNameBytes, 30);
  return header;
}

function buildZipCentralHeader({ fileNameBytes, crc, size, offset, timestamp }) {
  const header = new Uint8Array(46 + fileNameBytes.length);
  const view = new DataView(header.buffer);
  view.setUint32(0, 0x02014b50, true);
  view.setUint16(4, 20, true);
  view.setUint16(6, 20, true);
  view.setUint16(8, 0x0800, true);
  view.setUint16(10, 0, true);
  view.setUint16(12, timestamp.time, true);
  view.setUint16(14, timestamp.date, true);
  view.setUint32(16, crc, true);
  view.setUint32(20, size, true);
  view.setUint32(24, size, true);
  view.setUint16(28, fileNameBytes.length, true);
  view.setUint16(30, 0, true);
  view.setUint16(32, 0, true);
  view.setUint16(34, 0, true);
  view.setUint16(36, 0, true);
  view.setUint32(38, 0, true);
  view.setUint32(42, offset, true);
  header.set(fileNameBytes, 46);
  return header;
}

function buildZipEndRecord({ entryCount, centralSize, centralOffset }) {
  const record = new Uint8Array(22);
  const view = new DataView(record.buffer);
  view.setUint32(0, 0x06054b50, true);
  view.setUint16(4, 0, true);
  view.setUint16(6, 0, true);
  view.setUint16(8, entryCount, true);
  view.setUint16(10, entryCount, true);
  view.setUint32(12, centralSize, true);
  view.setUint32(16, centralOffset, true);
  view.setUint16(20, 0, true);
  return record;
}

function zipDosTimestamp(value) {
  const year = Math.max(1980, value.getFullYear());
  return {
    time: (value.getHours() << 11) | (value.getMinutes() << 5) | Math.floor(value.getSeconds() / 2),
    date: ((year - 1980) << 9) | ((value.getMonth() + 1) << 5) | value.getDate(),
  };
}

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc = ZIP_CRC32_TABLE[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function buildCrc32Table() {
  const table = new Uint32Array(256);
  for (let index = 0; index < 256; index += 1) {
    let value = index;
    for (let bit = 0; bit < 8; bit += 1) {
      value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
    }
    table[index] = value >>> 0;
  }
  return table;
}

function downloadBlob(blob, fileName) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = fileName;
  link.style.display = "none";
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}

function japaneseMonthText(value) {
  const text = safeText(value);
  const match = text.match(/^(\d{4})-(\d{2})/);
  if (!match) {
    return displayValue(text);
  }
  return `${match[1]}年${match[2]}月`;
}

function dutyDateText(value) {
  const text = safeText(value);
  const match = text.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (!match) {
    return displayValue(text);
  }

  const date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
  const weekday = ["日", "月", "火", "水", "木", "金", "土"][date.getDay()];
  return `${match[1]}/${match[2]}/${match[3]}（${weekday}）`;
}

function dutyWorkContent(detail) {
  const subject = safeText(detail.subject_name).trim();
  const content = safeText(detail.lesson_content).trim();
  if (subject && content) {
    return `${subject} / ${content}`;
  }
  return subject || content || "";
}

function timeOnly(value) {
  const text = safeText(value);
  return text ? text.slice(0, 5) : "";
}

function numberOrZero(value) {
  const numberValue = Number(value || 0);
  return Number.isFinite(numberValue) ? numberValue : 0;
}

function displayValue(value) {
  return safeText(value) || "-";
}
