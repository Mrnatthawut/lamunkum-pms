import "server-only";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import fontkit from "@pdf-lib/fontkit";
import { PDFDocument, rgb, type PDFFont, type PDFPage } from "pdf-lib";

const THAI_FONT = join(process.cwd(), "public/fonts/NotoSansThaiThai-Regular.woff");
const LATIN_FONT = join(process.cwd(), "public/fonts/NotoSansThaiLatin-Regular.woff");
const A4: [number, number] = [595.28, 841.89];
const MARGIN = 52;

function fontFor(character: string, thai: PDFFont, latin: PDFFont) { return /[\u0E00-\u0E7F]/.test(character) ? thai : latin; }
function textWidth(text: string, size: number, thai: PDFFont, latin: PDFFont) {
  return [...text].reduce((width, character) => width + fontFor(character, thai, latin).widthOfTextAtSize(character, size), 0);
}
function wrapLine(text: string, maxWidth: number, size: number, thai: PDFFont, latin: PDFFont) {
  const lines: string[] = []; let current = "";
  for (const character of [...text]) {
    if (current && textWidth(current + character, size, thai, latin) > maxWidth) { lines.push(current); current = character === " " ? "" : character; }
    else current += character;
  }
  lines.push(current); return lines;
}
function drawMixedText(page: PDFPage, text: string, x: number, y: number, size: number, thai: PDFFont, latin: PDFFont) {
  let cursor = x; let run = ""; let currentFont = fontFor(text[0] ?? " ", thai, latin);
  const flush = () => { if (!run) return; page.drawText(run, { x: cursor, y, size, font: currentFont, color: rgb(0.08, 0.12, 0.2) }); cursor += currentFont.widthOfTextAtSize(run, size); run = ""; };
  for (const character of [...text]) { const nextFont = fontFor(character, thai, latin); if (nextFont !== currentFont) { flush(); currentFont = nextFont; } run += character; }
  flush();
}

export interface PdfSignature { signerRole: string; signerName: string; signedAt: string; mimeType: string; bytes: Uint8Array }

export async function createThaiContractPdf(content: string, documentNumber: string, checksum: string, signatures: PdfSignature[] = []) {
  const pdf = await PDFDocument.create(); pdf.registerFontkit(fontkit);
  const [thaiBytes, latinBytes] = await Promise.all([readFile(THAI_FONT), readFile(LATIN_FONT)]);
  const thai = await pdf.embedFont(thaiBytes, { subset: true }); const latin = await pdf.embedFont(latinBytes, { subset: true });
  const size = 12; const lineHeight = 19; const maxWidth = A4[0] - MARGIN * 2;
  let page = pdf.addPage(A4); let y = A4[1] - MARGIN;
  for (const paragraph of content.replace(/\r\n/g, "\n").split("\n")) {
    const lines = paragraph ? wrapLine(paragraph, maxWidth, size, thai, latin) : [""];
    for (const line of lines) {
      if (y < MARGIN + 35) { page = pdf.addPage(A4); y = A4[1] - MARGIN; }
      if (line) drawMixedText(page, line, MARGIN, y, size, thai, latin);
      y -= lineHeight;
    }
  }
  if (signatures.length) {
    const signaturePage = pdf.addPage(A4); let signatureY = A4[1] - MARGIN;
    drawMixedText(signaturePage, "หลักฐานลายเซ็นอิเล็กทรอนิกส์", MARGIN, signatureY, 16, thai, latin); signatureY -= 38;
    drawMixedText(signaturePage, `เอกสาร ${documentNumber} · Checksum ${checksum}`, MARGIN, signatureY, 9, thai, latin); signatureY -= 42;
    for (const signature of signatures) {
      drawMixedText(signaturePage, `${signature.signerRole === "tenant" ? "ผู้เช่า" : "ผู้ให้เช่า"}: ${signature.signerName}`, MARGIN, signatureY, 12, thai, latin); signatureY -= 22;
      const image = signature.mimeType === "image/png" ? await pdf.embedPng(signature.bytes) : await pdf.embedJpg(signature.bytes);
      const scale = Math.min(220 / image.width, 90 / image.height, 1); signaturePage.drawImage(image, { x: MARGIN, y: signatureY - image.height * scale, width: image.width * scale, height: image.height * scale });
      signatureY -= 110; drawMixedText(signaturePage, `ลงนามเมื่อ ${new Intl.DateTimeFormat("th-TH", { dateStyle: "medium", timeStyle: "medium", timeZone: "Asia/Bangkok" }).format(new Date(signature.signedAt))}`, MARGIN, signatureY, 9, thai, latin); signatureY -= 42;
    }
    drawMixedText(signaturePage, "รายละเอียด IP และ User Agent จัดเก็บใน Audit Log และไม่แสดงในเอกสารดาวน์โหลด", MARGIN, 55, 8, thai, latin);
  }
  const pages = pdf.getPages();
  pages.forEach((item, index) => {
    drawMixedText(item, `${documentNumber} · หน้า ${index + 1}/${pages.length}`, MARGIN, 25, 8, thai, latin);
    drawMixedText(item, `Checksum ${checksum.slice(0, 16)}`, A4[0] - 190, 25, 8, thai, latin);
  });
  pdf.setTitle(`สัญญา ${documentNumber}`); pdf.setAuthor("Dormitory Management System"); pdf.setCreator("Dormitory Management System");
  return pdf.save();
}
