import { z } from "zod";

export const signatureSchema = z.object({
  documentId: z.string().uuid(), signerRole: z.enum(["owner","tenant"]), signerName: z.string().trim().min(2).max(150),
  signatureMethod: z.enum(["draw","upload"]), consent: z.literal("accepted"),
});

export const inspectionCategories = ["floor","wall","door","window","bathroom","air_conditioner","bed","wardrobe","desk","electrical","overall"] as const;
export const inspectionLabels: Record<typeof inspectionCategories[number], string> = { floor:"พื้น",wall:"ผนัง",door:"ประตู",window:"หน้าต่าง",bathroom:"ห้องน้ำ",air_conditioner:"เครื่องปรับอากาศ",bed:"เตียง",wardrobe:"ตู้",desk:"โต๊ะ",electrical:"เครื่องใช้ไฟฟ้า",overall:"ภาพรวม" };
const condition = z.enum(["good","damaged","missing","not_applicable"]);
export const inspectionItemSchema = z.object({ category: z.enum(inspectionCategories), condition, notes: z.string().trim().max(500) });

export interface SigningActionState { success?: boolean; message?: string; error?: string; fieldErrors?: Record<string,string[]|undefined> }
