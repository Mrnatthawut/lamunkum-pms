import { describe, expect, it } from "vitest";
import { createThaiContractPdf } from "@/lib/documents/pdf";
import { extractTemplateVariables, renderContractTemplate } from "@/lib/documents/template";

describe("Contract document generation", () => {
  it("แทนค่าตัวแปรและจัดรูปแบบวันที่/เงินบาท", () => {
    const rendered = renderContractTemplate("สัญญา {{contract_number}} วันที่ {{contract_date}} ค่าเช่า {{monthly_rent}} บาท", { contract_number: "CTR-2026-0001", contract_date: "2026-07-13", monthly_rent: "4500.00" });
    expect(rendered).toContain("CTR-2026-0001");
    expect(rendered).toContain("13 กรกฎาคม 2569");
    expect(rendered).toContain("4,500.00");
  });

  it("ตรวจพบตัวแปรใน Template โดยไม่ซ้ำ", () => {
    expect(extractTemplateVariables("{{tenant_name}} {{room_number}} {{tenant_name}}")).toEqual(["tenant_name", "room_number"]);
  });

  it("สร้าง PDF ภาษาไทยพร้อมฝังฟอนต์โดยไม่ใช้ screenshot", async () => {
    const bytes = await createThaiContractPdf("สัญญาเช่าห้องพัก\nเลขที่ CTR-2026-0001\nผู้เช่า สมชาย ทดสอบ", "CTR-2026-0001", "a".repeat(64));
    expect(new TextDecoder().decode(bytes.slice(0, 4))).toBe("%PDF");
    expect(bytes.byteLength).toBeGreaterThan(1000);
  });
});
