"use server";

import { revalidatePath } from "next/cache";
import { bootstrapOrganizationSchema, type BootstrapState } from "./schemas";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function bootstrapOrganizationAction(_state: BootstrapState, formData: FormData): Promise<BootstrapState> {
  const parsed = bootstrapOrganizationSchema.safeParse({ organizationName: formData.get("organizationName"), dormitoryName: formData.get("dormitoryName"), dormitoryCode: formData.get("dormitoryCode"), dormitoryAddress: formData.get("dormitoryAddress") });
  if (!parsed.success) return { fieldErrors: parsed.error.flatten().fieldErrors };
  const supabase = await createSupabaseServerClient();
  if (!supabase) return { error: "ยังไม่ได้ตั้งค่า Supabase" };
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Session หมดอายุ กรุณาเข้าสู่ระบบใหม่" };
  const { error } = await supabase.rpc("bootstrap_organization", { organization_name: parsed.data.organizationName, dormitory_name: parsed.data.dormitoryName, dormitory_code: parsed.data.dormitoryCode, dormitory_address: parsed.data.dormitoryAddress });
  if (error) return { error: error.message.includes("ALREADY_BOOTSTRAPPED") ? "บัญชีนี้ตั้งค่ากิจการแล้ว" : "ไม่สามารถสร้างกิจการได้ กรุณาตรวจสอบข้อมูลอีกครั้ง" };
  revalidatePath("/");
  return { success: true };
}
