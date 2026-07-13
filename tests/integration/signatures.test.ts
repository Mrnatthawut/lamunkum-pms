import { createHash, randomUUID } from "node:crypto";
import { createClient } from "@supabase/supabase-js";
import { describe, expect, it } from "vitest";

const suite = process.env.RUN_LOCAL_INTEGRATION === "1" ? describe : describe.skip;
suite("Contract signature และ inspection บน Supabase Local", () => {
  it("บันทึก inspection, private signature และล็อกเงื่อนไขสัญญา", async () => {
    const client = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL as string, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY as string);
    const { error: loginError } = await client.auth.signInWithPassword({ email: "owner@dormitory.local", password: "DormitoryLocal!2569" }); expect(loginError).toBeNull();
    const { data: contract } = await client.from("contracts").select("id,organization_id,dormitory_id,monthly_rent").eq("status", "active").limit(1).single(); expect(contract).toBeTruthy();
    const { data: document } = await client.from("generated_documents").select("id,checksum").eq("entity_id", contract?.id as string).eq("document_type", "contract").single(); expect(document).toBeTruthy();
    const { data: existingSignature } = await client.from("contract_signatures").select("id,storage_path").eq("generated_document_id", document?.id as string).eq("signer_role", "owner").maybeSingle();
    if (!existingSignature) {
      const bytes = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAF/gL+XfVQAAAAAElFTkSuQmCC", "base64");
      const inspection = await client.rpc("save_move_in_inspection", { target_contract_id: contract?.id, target_items: [{ category: "overall", condition: "good", notes: "ตรวจสอบจาก integration test" }] }); expect(inspection.error).toBeNull();
      const inspectionPath = `${contract?.organization_id}/${contract?.dormitory_id}/contracts/${contract?.id}/inspections/${randomUUID()}.png`;
      const inspectionUpload = await client.storage.from("room-inspections").upload(inspectionPath, bytes, { contentType: "image/png" }); expect(inspectionUpload.error).toBeNull();
      const { data: overall } = await client.from("room_asset_inspections").select("id").eq("contract_id", contract?.id as string).eq("category", "overall").single();
      const attachment = await client.from("room_inspection_attachments").insert({ organization_id: contract?.organization_id, dormitory_id: contract?.dormitory_id, inspection_id: overall?.id, storage_path: inspectionPath, mime_type: "image/png", size_bytes: bytes.byteLength, file_sha256: createHash("sha256").update(bytes).digest("hex") }); expect(attachment.error).toBeNull();
      const path = `${contract?.organization_id}/${contract?.dormitory_id}/contracts/${contract?.id}/${randomUUID()}.png`;
      const uploaded = await client.storage.from("contract-signatures").upload(path, bytes, { contentType: "image/png" }); expect(uploaded.error).toBeNull();
      const recorded = await client.rpc("record_contract_signature", { target_document_id: document?.id, target_signer_role: "owner", target_signer_name: "เจ้าของทดสอบระบบ", target_method: "upload", target_storage_path: path, target_mime_type: "image/png", target_size_bytes: bytes.byteLength, target_signature_sha256: createHash("sha256").update(bytes).digest("hex"), target_ip: "127.0.0.1", target_user_agent: "Vitest Integration" }); expect(recorded.error).toBeNull();
      const anonymous = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL as string, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY as string);
      const privateDownload = await anonymous.storage.from("contract-signatures").download(path); expect(privateDownload.error).toBeTruthy();
    }
    const update = await client.from("contracts").update({ monthly_rent: String(Number(contract?.monthly_rent) + 1) }).eq("id", contract?.id as string); expect(update.error?.message).toContain("SIGNED_CONTRACT_IMMUTABLE");
    const bypassInspection = await client.from("room_asset_inspections").update({ notes: "พยายามแก้หลังลงนาม" }).eq("contract_id", contract?.id as string).select("id"); expect(bypassInspection.data).toHaveLength(0);
    const { data: signature } = await client.from("contract_signatures").select("document_checksum,signature_sha256,ip,user_agent").eq("generated_document_id", document?.id as string).eq("signer_role", "owner").single();
    expect(signature?.document_checksum).toBe(document?.checksum); expect(signature?.signature_sha256).toMatch(/^[a-f0-9]{64}$/); expect(signature?.user_agent).toBe("Vitest Integration");
  });
});
