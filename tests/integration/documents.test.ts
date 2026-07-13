import { createClient } from "@supabase/supabase-js";
import { describe, expect, it } from "vitest";

const suite = process.env.RUN_LOCAL_INTEGRATION === "1" ? describe : describe.skip;
suite("Contract document snapshot บน Supabase Local", () => {
  it("สร้างเอกสารจาก Version ปัจจุบันแบบ idempotent และ immutable", async () => {
    const client = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL as string, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY as string);
    const { error: loginError } = await client.auth.signInWithPassword({ email: "owner@dormitory.local", password: "DormitoryLocal!2569" });
    expect(loginError).toBeNull();
    const { data: contract } = await client.from("contracts").select("id").eq("status", "active").limit(1).single();
    expect(contract).toBeTruthy();
    const first = await client.rpc("create_contract_document_snapshot", { target_contract_id: contract?.id });
    const second = await client.rpc("create_contract_document_snapshot", { target_contract_id: contract?.id });
    expect(first.error).toBeNull(); expect(second.error).toBeNull(); expect(second.data).toBe(first.data);
    const { data: document } = await client.from("generated_documents").select("checksum,template_snapshot,data_snapshot,contract_version_id").eq("id", first.data as string).single();
    expect(document?.checksum).toMatch(/^[a-f0-9]{64}$/);
    expect(document?.template_snapshot).toContain("{{contract_number}}");
    expect(document?.data_snapshot).toHaveProperty("contract_number");
    expect(document?.contract_version_id).toBeTruthy();
  });
});
