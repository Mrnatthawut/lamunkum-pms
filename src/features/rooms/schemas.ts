import { z } from "zod";

const code = z.string().trim().min(1, "กรุณาระบุรหัส").max(30).regex(/^[A-Za-z0-9_-]+$/, "ใช้ตัวอักษรอังกฤษ ตัวเลข _ หรือ - เท่านั้น");
const amount = z.string().trim().regex(/^\d{1,12}(\.\d{1,2})?$/, "กรุณาระบุจำนวนเงินที่ถูกต้อง");
const uuid = z.uuid("ข้อมูลอ้างอิงไม่ถูกต้อง");

export const createBuildingSchema = z.object({ code, name: z.string().trim().min(2, "กรุณาระบุชื่ออาคาร").max(120), floorCount: z.coerce.number().int().min(1).max(100) });
export const createRoomTypeSchema = z.object({ name: z.string().trim().min(2, "กรุณาระบุชื่อประเภทห้อง").max(120), baseRent: amount, deposit: amount, maxOccupants: z.coerce.number().int().min(1).max(20) });
export const createRoomSchema = z.object({ floorId: uuid, roomTypeId: uuid, code, roomNumber: z.string().trim().min(1, "กรุณาระบุหมายเลขห้อง").max(30), monthlyRent: amount, waterMeterNumber: z.string().trim().max(80).optional(), electricMeterNumber: z.string().trim().max(80).optional() });

export interface RoomActionState { success?: boolean; error?: string; fieldErrors?: Record<string, string[] | undefined> }
