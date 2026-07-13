"use server";

import { redirect } from "next/navigation";
import { loginSchema, type AuthActionState } from "@/features/auth/schemas";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function loginAction(_state: AuthActionState, formData: FormData): Promise<AuthActionState> {
  const parsed = loginSchema.safeParse({ email: formData.get("email"), password: formData.get("password") });
  if (!parsed.success) return { fieldErrors: parsed.error.flatten().fieldErrors };
  const supabase = await createSupabaseServerClient();
  if (!supabase) return { error: "ยังไม่ได้ตั้งค่า Supabase กรุณาตรวจสอบ .env.local" };
  const { error } = await supabase.auth.signInWithPassword(parsed.data);
  if (error) return { error: "อีเมลหรือรหัสผ่านไม่ถูกต้อง" };
  redirect("/");
}

export async function logoutAction() {
  const supabase = await createSupabaseServerClient();
  if (supabase) await supabase.auth.signOut();
  redirect("/login");
}
