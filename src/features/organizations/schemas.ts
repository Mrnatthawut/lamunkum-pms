import { z } from "zod";

export const bootstrapOrganizationSchema = z.object({
  organizationName: z.string().trim().min(2, "กรุณาระบุชื่อกิจการ").max(160),
  dormitoryName: z.string().trim().min(2, "กรุณาระบุชื่อหอพัก").max(160),
  dormitoryCode: z.string().trim().min(2).max(30).regex(/^[A-Za-z0-9_-]+$/, "ใช้ตัวอักษรอังกฤษ ตัวเลข _ หรือ - เท่านั้น"),
  dormitoryAddress: z.string().trim().min(5, "กรุณาระบุที่อยู่").max(1000),
});

export interface BootstrapState { error?: string; success?: boolean; fieldErrors?: Record<string, string[] | undefined> }
