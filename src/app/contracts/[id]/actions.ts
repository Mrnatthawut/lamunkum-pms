"use server";

import { randomUUID } from "node:crypto";
import { headers } from "next/headers";
import { revalidatePath } from "next/cache";
import { inspectionCategories, inspectionItemSchema, signatureSchema, type SigningActionState } from "@/features/contracts/signature-schemas";
import { requireDormitoryContext } from "@/lib/auth/context";
import { validateImageFile } from "@/lib/security/uploads";

function errorState(error: unknown): SigningActionState {
  const message = error instanceof Error ? error.message : "";
  if (message.includes("INVALID_FILE_SIZE")) return { error: "ไฟล์มีขนาดไม่ถูกต้องหรือลายเซ็นเกิน 2 MB" };
  if (message.includes("INVALID_FILE_TYPE") || message.includes("MIME_MISMATCH")) return { error: "รองรับเฉพาะรูป PNG/JPEG ที่ตรวจสอบชนิดไฟล์ได้" };
  if (message.includes("23505") || message.includes("duplicate")) return { error: "ผู้ลงนามประเภทนี้ลงนามในเอกสารแล้ว" };
  if (message.includes("CONTRACT_ALREADY_SIGNED")) return { error: "สัญญาลงนามแล้ว ไม่สามารถแก้แบบตรวจรับห้องได้" };
  return { error: "ไม่สามารถบันทึกได้ กรุณาตรวจสอบข้อมูลและลองอีกครั้ง" };
}

function requestIp(headersList: Headers) {
  const value = (headersList.get("x-forwarded-for")?.split(",")[0] ?? headersList.get("x-real-ip") ?? "").trim();
  return /^[0-9a-f:.]{2,45}$/i.test(value) ? value : null;
}

export async function signContractAction(_state: SigningActionState, formData: FormData): Promise<SigningActionState> {
  const parsed = signatureSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { fieldErrors: parsed.error.flatten().fieldErrors, error: "กรุณาระบุข้อมูลและยอมรับข้อความการลงนาม" };
  let uploadedPath = "";
  try {
    const file = formData.get("signatureFile"); if (!(file instanceof File)) throw new Error("INVALID_FILE_TYPE");
    const image = await validateImageFile(file, { maxBytes: 2 * 1024 * 1024, allowWebp: false });
    const context = await requireDormitoryContext("contracts.manage");
    const { data: document, error: documentError } = await context.supabase.from("generated_documents").select("id,entity_id").eq("id", parsed.data.documentId).eq("dormitory_id", context.dormitoryId).eq("document_type", "contract").single();
    if (documentError || !document) throw new Error("DOCUMENT_NOT_FOUND");
    uploadedPath = `${context.organizationId}/${context.dormitoryId}/contracts/${document.entity_id}/${randomUUID()}.${image.extension}`;
    const uploaded = await context.supabase.storage.from("contract-signatures").upload(uploadedPath, image.bytes, { contentType: image.mimeType, upsert: false, cacheControl: "3600" });
    if (uploaded.error) throw uploaded.error;
    const headersList = await headers();
    const { error } = await context.supabase.rpc("record_contract_signature", { target_document_id: document.id, target_signer_role: parsed.data.signerRole, target_signer_name: parsed.data.signerName, target_method: parsed.data.signatureMethod, target_storage_path: uploadedPath, target_mime_type: image.mimeType, target_size_bytes: image.size, target_signature_sha256: image.sha256, target_ip: requestIp(headersList), target_user_agent: headersList.get("user-agent") ?? "" });
    if (error) { await context.supabase.storage.from("contract-signatures").remove([uploadedPath]); throw error; }
    revalidatePath(`/contracts/${document.entity_id}`); revalidatePath("/contracts");
    return { success: true, message: "บันทึกลายเซ็นและหลักฐานการลงนามสำเร็จ" };
  } catch (error) { return errorState(error); }
}

export async function saveInspectionAction(_state: SigningActionState, formData: FormData): Promise<SigningActionState> {
  try {
    const contractId = String(formData.get("contractId") ?? ""); if (!/^[0-9a-f-]{36}$/i.test(contractId)) throw new Error("INVALID_CONTRACT");
    const items = inspectionCategories.map((category) => inspectionItemSchema.parse({ category, condition: formData.get(`condition_${category}`), notes: formData.get(`notes_${category}`) ?? "" }));
    const photos = formData.getAll("inspectionPhotos").filter((item): item is File => item instanceof File && item.size > 0);
    if (photos.length > 5) return { error: "แนบรูปได้ไม่เกิน 5 รูปต่อครั้ง" };
    const validatedPhotos = await Promise.all(photos.map((file) => validateImageFile(file, { maxBytes: 5 * 1024 * 1024, allowWebp: true })));
    const context = await requireDormitoryContext("contracts.manage");
    const { error: rpcError } = await context.supabase.rpc("save_move_in_inspection", { target_contract_id: contractId, target_items: items });
    if (rpcError) throw rpcError;
    if (validatedPhotos.length) {
      const { data: overall } = await context.supabase.from("room_asset_inspections").select("id").eq("contract_id", contractId).eq("category", "overall").single();
      if (!overall) throw new Error("INSPECTION_NOT_FOUND");
      for (const photo of validatedPhotos) {
        const path = `${context.organizationId}/${context.dormitoryId}/contracts/${contractId}/inspections/${randomUUID()}.${photo.extension}`;
        const upload = await context.supabase.storage.from("room-inspections").upload(path, photo.bytes, { contentType: photo.mimeType, upsert: false, cacheControl: "3600" });
        if (upload.error) throw upload.error;
        const inserted = await context.supabase.from("room_inspection_attachments").insert({ organization_id: context.organizationId, dormitory_id: context.dormitoryId, inspection_id: overall.id, storage_path: path, mime_type: photo.mimeType, size_bytes: photo.size, file_sha256: photo.sha256, created_by: context.user.id });
        if (inserted.error) { await context.supabase.storage.from("room-inspections").remove([path]); throw inserted.error; }
      }
    }
    revalidatePath(`/contracts/${contractId}`); return { success: true, message: `บันทึกแบบตรวจรับห้องสำเร็จ${validatedPhotos.length ? ` พร้อมรูป ${validatedPhotos.length} รูป` : ""}` };
  } catch (error) { return errorState(error); }
}
