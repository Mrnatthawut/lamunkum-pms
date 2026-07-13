import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function requirePermission(permission: string) {
  const supabase = await createSupabaseServerClient();
  if (!supabase) throw new Error("SUPABASE_NOT_CONFIGURED");
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("UNAUTHENTICATED");
  const { data, error } = await supabase.rpc("has_permission", { permission_code: permission });
  if (error || !data) throw new Error("FORBIDDEN");
  return { supabase, user };
}
