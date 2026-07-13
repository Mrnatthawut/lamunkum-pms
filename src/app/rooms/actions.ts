"use server";

import { revalidatePath } from "next/cache";
import { requireDormitoryContext } from "@/lib/auth/context";
import { RoomService } from "@/services/room-service";
import { createBuildingSchema, createRoomSchema, createRoomTypeSchema, type RoomActionState } from "@/features/rooms/schemas";

function actionError(error: unknown): RoomActionState {
  const message = error instanceof Error ? error.message : "";
  if (message.includes("23505") || message.toLowerCase().includes("duplicate")) return { error: "รหัสหรือหมายเลขนี้ถูกใช้งานแล้ว" };
  if (message.includes("FORBIDDEN")) return { error: "คุณไม่มีสิทธิ์ดำเนินการ" };
  if (message.includes("MISMATCH")) return { error: "อาคาร ชั้น หรือประเภทห้องไม่สัมพันธ์กัน" };
  return { error: "ไม่สามารถบันทึกได้ กรุณาตรวจสอบข้อมูลอีกครั้ง" };
}

export async function createBuildingAction(_state: RoomActionState, formData: FormData): Promise<RoomActionState> {
  const parsed = createBuildingSchema.safeParse({ code: formData.get("code"), name: formData.get("name"), floorCount: formData.get("floorCount") });
  if (!parsed.success) return { fieldErrors: parsed.error.flatten().fieldErrors };
  try { const context = await requireDormitoryContext("rooms.create"); await new RoomService(context.supabase, context).createBuilding(parsed.data); revalidatePath("/rooms"); return { success: true }; } catch (error) { return actionError(error); }
}

export async function createRoomTypeAction(_state: RoomActionState, formData: FormData): Promise<RoomActionState> {
  const parsed = createRoomTypeSchema.safeParse({ name: formData.get("name"), baseRent: formData.get("baseRent"), deposit: formData.get("deposit"), maxOccupants: formData.get("maxOccupants") });
  if (!parsed.success) return { fieldErrors: parsed.error.flatten().fieldErrors };
  try { const context = await requireDormitoryContext("rooms.create"); await new RoomService(context.supabase, context).createRoomType(parsed.data); revalidatePath("/rooms"); return { success: true }; } catch (error) { return actionError(error); }
}

export async function createRoomAction(_state: RoomActionState, formData: FormData): Promise<RoomActionState> {
  const parsed = createRoomSchema.safeParse({ floorId: formData.get("floorId"), roomTypeId: formData.get("roomTypeId"), code: formData.get("code"), roomNumber: formData.get("roomNumber"), monthlyRent: formData.get("monthlyRent"), waterMeterNumber: formData.get("waterMeterNumber"), electricMeterNumber: formData.get("electricMeterNumber") });
  if (!parsed.success) return { fieldErrors: parsed.error.flatten().fieldErrors };
  try { const context = await requireDormitoryContext("rooms.create"); await new RoomService(context.supabase, context).createRoom(parsed.data); revalidatePath("/rooms"); revalidatePath("/"); return { success: true }; } catch (error) { return actionError(error); }
}
