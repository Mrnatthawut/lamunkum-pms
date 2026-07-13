import { describe, expect, it } from "vitest";
import { calculateUsage, calculateTieredCharge } from "../src/features/meters/calculations";
import { calculateInvoice, calculateLateFee } from "../src/features/billing/calculations";
import { validateAllocations } from "../src/features/payments/calculations";

describe("กฎธุรกิจการเงินและมิเตอร์", () => {
 it("คำนวณหน่วยและปฏิเสธค่ามิเตอร์ย้อนหลัง", () => { expect(calculateUsage("100", "112.5")).toBe("12.500"); expect(() => calculateUsage("100", "99")).toThrow("METER_READING_DECREASED"); });
 it("คำนวณขั้นบันไดและขั้นต่ำ", () => { expect(calculateTieredCharge("15", [{fromUnit:"0",toUnit:"10",pricePerUnit:"5"},{fromUnit:"10",toUnit:null,pricePerUnit:"8"}])).toBe("90.00"); expect(calculateTieredCharge("1", [{fromUnit:"0",toUnit:null,pricePerUnit:"5"}], "100")).toBe("100.00"); });
 it("รวมบิลโดยไม่ใช้ floating point", () => { expect(calculateInvoice([{quantity:"2",unitPrice:"100.10",discount:"0.20",taxRate:"7"}], "50")).toEqual({subtotal:"200.20",discount:"0.20",tax:"14.00",total:"264.00"}); });
 it("คำนวณค่าปรับพร้อม grace และเพดาน", () => { expect(calculateLateFee("1000", 10, {type:"daily",value:"20",graceDays:3,maximum:"100"})).toBe("100.00"); });
 it("ป้องกัน allocation เกินยอดและคืนเครดิต", () => { expect(validateAllocations("1000", [{invoiceBalance:"800",amount:"700"}])).toEqual({allocated:"700.00",credit:"300.00"}); expect(() => validateAllocations("100", [{invoiceBalance:"90",amount:"100"}])).toThrow(); });
});
