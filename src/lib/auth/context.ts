import { requirePermission } from "./authorize";

export async function requireDormitoryContext(permission: string) {
  const { supabase, user } = await requirePermission(permission);
  const { data: membership, error: membershipError } = await supabase
    .from("organization_members")
    .select("organization_id,role")
    .eq("profile_id", user.id)
    .eq("active", true)
    .limit(1)
    .single();
  if (membershipError || !membership) throw new Error("ORGANIZATION_REQUIRED");
  const { data: allowed } = await supabase.rpc("has_org_permission", { target_organization_id: membership.organization_id, permission_code: permission });
  if (!allowed) throw new Error("FORBIDDEN");
  const { data: dormitory, error: dormitoryError } = await supabase
    .from("dormitories")
    .select("id,name")
    .eq("organization_id", membership.organization_id)
    .is("deleted_at", null)
    .order("created_at")
    .limit(1)
    .single();
  if (dormitoryError || !dormitory) throw new Error("DORMITORY_REQUIRED");
  return { supabase, user, organizationId: membership.organization_id, dormitoryId: dormitory.id, dormitoryName: dormitory.name, role: membership.role };
}
