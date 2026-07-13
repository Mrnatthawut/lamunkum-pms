import { z } from "zod";

const money = z.string().trim().regex(/^\d{1,12}(\.\d{1,2})?$/, "กรุณาระบุจำนวนเงินให้ถูกต้อง");
const reading = z.string().trim().regex(/^\d{1,12}(\.\d{1,3})?$/, "กรุณาระบุค่ามิเตอร์ให้ถูกต้อง");
const optionalUuid = z.preprocess((value) => value === "" ? undefined : value, z.string().uuid().optional());

export const createReservationSchema = z.object({
  roomId: z.string().uuid("กรุณาเลือกห้อง"),
  tenantId: z.string().uuid("กรุณาเลือกผู้เช่า"),
  expectedMoveInDate: z.string().date("กรุณาระบุวันที่เข้าอยู่"),
  bookingAmount: money,
  paymentMethod: z.string().trim().max(50).optional().default(""),
  expiresAt: z.string().datetime({ local: true, message: "กรุณาระบุวันหมดอายุ" }),
  status: z.enum(["pending_payment", "confirmed"]),
  notes: z.string().trim().max(1000).optional().default(""),
}).superRefine((value, context) => {
  if (new Date(value.expiresAt).getTime() <= Date.now()) context.addIssue({ code: "custom", path: ["expiresAt"], message: "วันหมดอายุต้องอยู่ในอนาคต" });
});

export const createContractSchema = z.object({
  reservationId: optionalUuid,
  roomId: z.string().uuid("กรุณาเลือกห้อง"),
  tenantId: z.string().uuid("กรุณาเลือกผู้เช่า"),
  contractDate: z.string().date("กรุณาระบุวันที่ทำสัญญา"),
  startDate: z.string().date("กรุณาระบุวันที่เริ่มสัญญา"),
  endDate: z.string().date("กรุณาระบุวันที่สิ้นสุดสัญญา"),
  monthlyRent: money,
  deposit: money,
  advanceRent: money,
  dueDay: z.coerce.number().int().min(1).max(28),
  noticeDays: z.coerce.number().int().min(0).max(365),
  initialWater: reading,
  initialElectric: reading,
  inspectionNotes: z.string().trim().max(2000).optional().default(""),
  notes: z.string().trim().max(2000).optional().default(""),
}).superRefine((value, context) => {
  if (value.endDate <= value.startDate) context.addIssue({ code: "custom", path: ["endDate"], message: "วันที่สิ้นสุดต้องหลังวันที่เริ่มสัญญา" });
  if (value.contractDate > value.startDate) context.addIssue({ code: "custom", path: ["contractDate"], message: "วันที่ทำสัญญาต้องไม่หลังวันเริ่มสัญญา" });
});

export interface ContractActionState {
  success?: boolean;
  message?: string;
  error?: string;
  fieldErrors?: Record<string, string[] | undefined>;
}

export type ReservationInput = z.infer<typeof createReservationSchema>;
export type ContractInput = z.infer<typeof createContractSchema>;
