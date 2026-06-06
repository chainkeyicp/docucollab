const MAX_EXTRACTED_CHARS = 90_000;

const TEXT_EXTENSIONS = new Set([
  "txt",
  "md",
  "markdown",
  "json",
  "html",
  "htm",
  "xml",
  "log",
  "yaml",
  "yml",
]);

const DELIMITED_EXTENSIONS = new Set(["csv", "tsv"]);
const XLSX_EXTENSIONS = new Set(["xlsx"]);
const IMAGE_EXTENSIONS = new Set(["png", "jpg", "jpeg", "webp", "gif", "bmp", "tiff", "tif"]);

export async function extractTextFromFile(file, options = {}) {
  const arrayBuffer = await file.arrayBuffer();
  return extractTextFromBytes(arrayBuffer, {
    name: file.name,
    mimeType: file.type,
    ...options,
  });
}

export async function extractTextFromBytes(bytes, options = {}) {
  const arrayBuffer = toArrayBuffer(bytes);
  const name = options.name || "";
  const mimeType = options.mimeType || "";
  const format = detectFormat(name, mimeType);

  try {
    if (format === "pdf") {
      return await extractPdfText(arrayBuffer, options);
    }

    if (format === "docx") {
      return await extractDocxText(arrayBuffer, options);
    }

    if (format === "delimited") {
      return extractDelimitedText(arrayBuffer, options);
    }

    if (format === "xlsx") {
      return await extractXlsxText(arrayBuffer, options);
    }

    if (format === "text") {
      return finalizeText(decodeText(arrayBuffer), {
        format,
        method: "text-decoder",
        maxChars: options.maxChars,
      });
    }

    if (format === "image") {
      return emptyResult({
        format,
        method: "ocr-required",
        warnings: ["Images need OCR before AI analysis. OCR support is planned next."],
      });
    }

    return emptyResult({
      format,
      method: "unsupported",
      warnings: ["This file type does not expose readable text yet."],
    });
  } catch (error) {
    return emptyResult({
      format,
      method: "failed",
      warnings: [`Text extraction failed: ${error.message}`],
    });
  }
}

export function describeExtraction(extraction) {
  if (!extraction) return "";

  if (extraction.text) {
    const format = extraction.format === "xlsx" || extraction.format === "delimited"
      ? "spreadsheet"
      : extraction.format.toUpperCase();
    const suffix = extraction.stats.truncated ? " (truncated for AI)" : "";
    return `${format} text extracted: ${extraction.stats.charCount.toLocaleString()} chars${suffix}`;
  }

  return extraction.warnings[0] || "No readable text extracted.";
}

export function isAiReadable(extraction) {
  return Boolean(extraction?.text?.trim());
}

function detectFormat(name, mimeType) {
  const ext = extensionOf(name);
  const type = (mimeType || "").toLowerCase();

  if (type === "application/pdf" || ext === "pdf") return "pdf";
  if (
    type === "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ||
    ext === "docx"
  ) return "docx";
  if (
    type === "text/csv" ||
    type === "text/tab-separated-values" ||
    DELIMITED_EXTENSIONS.has(ext)
  ) return "delimited";
  if (
    type === "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" ||
    XLSX_EXTENSIONS.has(ext)
  ) return "xlsx";
  if (type.startsWith("text/") || TEXT_EXTENSIONS.has(ext)) return "text";
  if (type.startsWith("image/") || IMAGE_EXTENSIONS.has(ext)) return "image";
  return ext || "unknown";
}

async function extractPdfText(arrayBuffer, options) {
  const pdfjs = await import("pdfjs-dist/build/pdf.mjs");
  pdfjs.GlobalWorkerOptions.workerSrc = new URL("pdfjs-dist/build/pdf.worker.mjs", import.meta.url).toString();

  const pdf = await pdfjs.getDocument({ data: new Uint8Array(arrayBuffer) }).promise;
  const pages = [];

  for (let pageNumber = 1; pageNumber <= pdf.numPages; pageNumber += 1) {
    const page = await pdf.getPage(pageNumber);
    const content = await page.getTextContent();
    const text = content.items
      .map((item) => {
        const value = "str" in item ? item.str : "";
        return item.hasEOL ? `${value}\n` : `${value} `;
      })
      .join("")
      .replace(/[ \t]+\n/g, "\n")
      .replace(/\n{3,}/g, "\n\n")
      .trim();

    if (text) pages.push(`Page ${pageNumber}\n${text}`);
  }

  return finalizeText(pages.join("\n\n"), {
    format: "pdf",
    method: "pdfjs-dist",
    maxChars: options.maxChars,
    warnings: pages.length === 0 ? ["No selectable PDF text found. This may be a scanned PDF that needs OCR."] : [],
    stats: { pageCount: pdf.numPages },
  });
}

async function extractDocxText(arrayBuffer, options) {
  const mammothModule = await import("mammoth/mammoth.browser.js");
  const mammoth = mammothModule.default || mammothModule;
  const result = await mammoth.extractRawText({ arrayBuffer });
  const warnings = (result.messages || []).map((message) => message.message).filter(Boolean);

  return finalizeText(result.value || "", {
    format: "docx",
    method: "mammoth",
    maxChars: options.maxChars,
    warnings,
  });
}

function extractDelimitedText(arrayBuffer, options) {
  const text = decodeText(arrayBuffer);
  const delimiter = extensionOf(options.name) === "tsv" ? "\t" : ",";
  const normalized = text
    .split("\n")
    .map((line) => line.split(delimiter).map((cell) => cell.trim()).join("\t").trim())
    .filter(Boolean)
    .join("\n");

  return finalizeText(normalized, {
    format: "delimited",
    method: delimiter === "\t" ? "tsv-text" : "csv-text",
    maxChars: options.maxChars,
  });
}

async function extractXlsxText(arrayBuffer, options) {
  const readExcelModule = await import("read-excel-file/browser");
  const readExcelFile = readExcelModule.default;
  const sheets = await readExcelFile(arrayBuffer);
  const parts = sheets.map(({ sheet, data }) => {
    const body = data
      .map((row) => row.map((cell) => formatCell(cell)).join("\t").trim())
      .filter(Boolean)
      .join("\n");
    return body ? `Sheet: ${sheet}\n${body}` : "";
  }).filter(Boolean);

  return finalizeText(parts.join("\n\n"), {
    format: "xlsx",
    method: "read-excel-file",
    maxChars: options.maxChars,
    warnings: parts.length === 0 ? ["No readable spreadsheet cells found."] : [],
    stats: { sheetCount: sheets.length },
  });
}

function formatCell(cell) {
  if (cell == null) return "";
  if (cell instanceof Date) return cell.toISOString().slice(0, 10);
  return String(cell).trim();
}

function finalizeText(rawText, options) {
  const maxChars = options.maxChars || MAX_EXTRACTED_CHARS;
  const warnings = [...(options.warnings || [])];
  const text = normalizeWhitespace(rawText);
  const truncated = text.length > maxChars;
  const finalText = truncated ? text.slice(0, maxChars) : text;

  if (!finalText.trim()) {
    return emptyResult({
      format: options.format,
      method: options.method,
      warnings: warnings.length > 0 ? warnings : ["No readable text found."],
      stats: options.stats,
    });
  }

  if (truncated) {
    warnings.push(`Extracted text was limited to ${maxChars.toLocaleString()} characters for AI processing.`);
  }

  return {
    text: finalText,
    format: options.format,
    method: options.method,
    warnings,
    stats: {
      ...(options.stats || {}),
      charCount: finalText.length,
      originalCharCount: text.length,
      truncated,
    },
  };
}

function emptyResult({ format, method, warnings = [], stats = {} }) {
  return {
    text: "",
    format,
    method,
    warnings,
    stats: {
      ...stats,
      charCount: 0,
      originalCharCount: 0,
      truncated: false,
    },
  };
}

function toArrayBuffer(bytes) {
  if (bytes instanceof ArrayBuffer) return bytes;
  if (ArrayBuffer.isView(bytes)) {
    return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  }
  throw new Error("Unsupported byte source");
}

function decodeText(arrayBuffer) {
  return new TextDecoder("utf-8", { fatal: false }).decode(arrayBuffer);
}

function normalizeWhitespace(text) {
  return text
    .replace(/\u0000/g, "")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{4,}/g, "\n\n\n")
    .trim();
}

function extensionOf(name) {
  const normalized = (name || "").toLowerCase();
  const index = normalized.lastIndexOf(".");
  return index >= 0 ? normalized.slice(index + 1) : "";
}
