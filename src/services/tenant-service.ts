import type { SupabaseClient } from "@supabase/supabase-js";
import { encryptPii } from "@/lib/security/pii";
import type { z } from "zod";
import type { createTenantSchema } from "@/features/tenants/schemas";

type CreateTenantInput = z.infer<typeof createTenantSchema>;
export class TenantService {
  constructor(private readonly db: SupabaseClient, private readonly dormitoryId: string) {}
  async create(input: CreateTenantInput) {
    const document = input.documentNumber.toUpperCase();
    const encrypted = document ? encryptPii(document) : "";
    const { data,error } = await this.db.rpc("create_tenant_with_emergency_contact", {
      target_dormitory_id:this.dormitoryId, tenant_title:input.title, tenant_first_name:input.firstName, tenant_last_name:input.lastName,
      tenant_nickname:input.nickname, tenant_phone:input.phone, tenant_email:input.email, tenant_id_type:input.idType,
      tenant_identity_encrypted:encrypted, tenant_identity_last4:document.slice(-4), tenant_birth_date:input.birthDate || null,
      tenant_registered_address:input.registeredAddress, tenant_current_address:input.currentAddress, tenant_occupation:input.occupation,
      tenant_workplace:input.workplace, tenant_vehicle_registration:input.vehicleRegistration, tenant_notes:input.notes,
      emergency_name:input.emergencyName, emergency_relationship:input.emergencyRelationship, emergency_phone:input.emergencyPhone,
    });
    if (error) throw error;
    return data as string;
  }
}
