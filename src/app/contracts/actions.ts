"use server";

import { revalidatePath } from "next/cache";
import { createContractSchema, createReservationSchema, type ContractActionState } from "@/features/contracts/schemas";
import { requireDormitoryContext } from "@/lib/auth/context";
import { ContractService } from "@/services/contract-service";
import { contractTemplateSchema } from "@/features/contracts/template-schemas";

function actionError(error: unknown): ContractActionState {
  const message = error instanceof Error ? error.message : "";
  if (message.includes("ROOM_NOT_AVAILABLE") || message.includes("23505")) return { error: "ห้องนี้ถูกจองหรือมีสัญญาใช้งานแล้ว กรุณาเลือกห้องอื่น" };
  if (message.includes("RESERVATION_NOT_CONFIRMED")) return { error: "กรุณายืนยันการจองก่อนสร้างสัญญา" };
  if (message.includes("MISMATCH")) return { error: "ข้อมูลห้อง ผู้เช่า หรือการจองไม่สัมพันธ์กัน" };
  if (message.includes("INVALID_")) return { error: "ข้อมูลไม่ผ่านเงื่อนไข กรุณาตรวจสอบวันที่และจำนวนเงิน" };
  if (message.includes("FORBIDDEN")) return { error: "คุณไม่มีสิทธิ์จัดการสัญญา" };
  return { error: "ไม่สามารถดำเนินการได้ กรุณาตรวจสอบข้อมูลอีกครั้ง" };
}

function refreshContracts() { revalidatePath("/contracts"); revalidatePath("/rooms"); revalidatePath("/"); }

export async function createReservationAction(_state: ContractActionState, formData: FormData): Promise<ContractActionState> {
  const parsed = createReservationSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { fieldErrors: parsed.error.flatten().fieldErrors };
  try {
    const context = await requireDormitoryContext("contracts.manage");
    await new ContractService(context.supabase, context).createReservation(parsed.data);
    refreshContracts();
    return { success: true, message: "สร้างการจองสำเร็จ" };
  } catch (error) { return actionError(error); }
}

export async function updateReservationStatusAction(formData: FormData) {
  const reservationId = String(formData.get("reservationId") ?? "");
  const status = String(formData.get("status") ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(reservationId) || !["confirmed", "cancelled"].includes(status)) return;
  const context = await requireDormitoryContext("contracts.manage");
  await new ContractService(context.supabase, context).setReservationStatus(reservationId, status as "confirmed" | "cancelled", String(formData.get("reason") ?? ""));
  refreshContracts();
}

export async function createContractAction(_state: ContractActionState, formData: FormData): Promise<ContractActionState> {
  const parsed = createContractSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { fieldErrors: parsed.error.flatten().fieldErrors };
  try {
    const context = await requireDormitoryContext("contracts.manage");
    const contractId = await new ContractService(context.supabase, context).createActiveContract(parsed.data);
    refreshContracts();
    return { success: true, message: `สร้างสัญญาและย้ายเข้าสำเร็จ (${contractId.slice(0, 8)})` };
  } catch (error) { return actionError(error); }
}

export async function createContractTemplateVersionAction(_state: ContractActionState, formData: FormData): Promise<ContractActionState> {
  const parsed = contractTemplateSchema.safeParse({ name: formData.get("name"), body: formData.get("body") });
  if (!parsed.success) return { fieldErrors: parsed.error.flatten().fieldErrors };
  try {
    const context = await requireDormitoryContext("contracts.manage");
    const { error } = await context.supabase.rpc("create_contract_template_version", { target_dormitory_id: context.dormitoryId, target_name: parsed.data.name, target_body: parsed.data.body });
    if (error) throw error;
    revalidatePath("/contracts/templates"); return { success: true, message: "สร้าง Template Version ใหม่สำเร็จ" };
  } catch (error) { return actionError(error); }
}

export async function generateContractDocumentAction(formData: FormData) {
  const contractId = String(formData.get("contractId") ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(contractId)) return;
  const context = await requireDormitoryContext("contracts.manage");
  const { error } = await context.supabase.rpc("create_contract_document_snapshot", { target_contract_id: contractId });
  if (error) throw new Error("DOCUMENT_GENERATION_FAILED");
  revalidatePath("/contracts");
}
