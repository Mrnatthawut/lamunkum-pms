import { describe, expect, it } from "vitest";
import { createContractSchema, createReservationSchema } from "@/features/contracts/schemas";

const id = "11111111-1111-4111-8111-111111111111";

describe("Contract workflow validation", () => {
  it("รับข้อมูลการจองที่ถูกต้อง", () => {
    expect(createReservationSchema.safeParse({ roomId: id, tenantId: id, expectedMoveInDate: "2999-01-01", bookingAmount: "1000.00", paymentMethod: "cash", expiresAt: "2999-01-01T12:00", status: "confirmed", notes: "" }).success).toBe(true);
  });

  it("ปฏิเสธวันสิ้นสุดสัญญาที่มาก่อนวันเริ่ม", () => {
    const result = createContractSchema.safeParse({ reservationId: "", roomId: id, tenantId: id, contractDate: "2026-07-01", startDate: "2026-07-01", endDate: "2026-06-30", monthlyRent: "4500.00", deposit: "4500.00", advanceRent: "0.00", dueDay: "5", noticeDays: "30", initialWater: "1.000", initialElectric: "2.000", inspectionNotes: "", notes: "" });
    expect(result.success).toBe(false);
  });

  it("ปฏิเสธเงินที่มีทศนิยมเกินสองตำแหน่ง", () => {
    const result = createReservationSchema.safeParse({ roomId: id, tenantId: id, expectedMoveInDate: "2999-01-01", bookingAmount: "100.999", paymentMethod: "", expiresAt: "2999-01-01T12:00", status: "pending_payment", notes: "" });
    expect(result.success).toBe(false);
  });
});
