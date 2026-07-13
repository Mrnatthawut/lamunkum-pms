import { z } from "zod";
import { extractTemplateVariables } from "@/lib/documents/template";

export const allowedContractVariables = ["organization_name","dormitory_name","dormitory_address","contract_number","contract_date","tenant_name","tenant_phone","tenant_address","room_number","start_date","end_date","monthly_rent","deposit","advance_rent","due_day","notice_days","initial_water","initial_electric","inspection_notes","contract_notes"] as const;
export const contractTemplateSchema = z.object({ name: z.string().trim().min(3).max(100), body: z.string().min(100).max(30000) }).superRefine((value, context) => {
  const unknown = extractTemplateVariables(value.body).filter((item) => !allowedContractVariables.includes(item as typeof allowedContractVariables[number]));
  if (unknown.length) context.addIssue({ code: "custom", path: ["body"], message: `พบตัวแปรที่ไม่รองรับ: ${unknown.join(", ")}` });
});
