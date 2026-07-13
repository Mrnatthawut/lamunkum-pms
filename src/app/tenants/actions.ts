"use server";

import { revalidatePath } from "next/cache";
import { requireDormitoryContext } from "@/lib/auth/context";
import { createTenantSchema, type TenantActionState } from "@/features/tenants/schemas";
import { TenantService } from "@/services/tenant-service";

export async function createTenantAction(_state: TenantActionState, formData: FormData): Promise<TenantActionState> {
  const values = Object.fromEntries(["title","firstName","lastName","nickname","phone","email","idType","documentNumber","birthDate","registeredAddress","currentAddress","occupation","workplace","vehicleRegistration","notes","emergencyName","emergencyRelationship","emergencyPhone"].map(key=>[key,formData.get(key)??""]));
  const parsed = createTenantSchema.safeParse(values);
  if (!parsed.success) return {fieldErrors:parsed.error.flatten().fieldErrors};
  try { const context=await requireDormitoryContext("tenants.create"); await new TenantService(context.supabase,context.dormitoryId).create(parsed.data); revalidatePath("/tenants"); return {success:true}; }
  catch(error) { const message=error instanceof Error?error.message:""; if(message.includes("ENCRYPTION_KEY")) return {error:"ยังไม่ได้ตั้งค่ากุญแจเข้ารหัสข้อมูลส่วนบุคคล"}; if(message.includes("23505")||message.toLowerCase().includes("duplicate")) return {error:"ข้อมูลผู้เช่านี้มีอยู่แล้ว"}; return {error:"ไม่สามารถบันทึกผู้เช่าได้ กรุณาตรวจสอบข้อมูลอีกครั้ง"}; }
}
