"use client";

import { useActionState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { Building2, DoorOpen, Layers3, LoaderCircle } from "lucide-react";
import { createBuildingAction, createRoomAction, createRoomTypeAction } from "@/app/rooms/actions";
import type { RoomActionState } from "@/features/rooms/schemas";

interface FloorOption { id: string; floor_number: number; name: string | null }
interface BuildingOption { id: string; code: string; name: string; floors: FloorOption[] }
interface RoomTypeOption { id: string; name: string; base_rent: number | string; deposit: number | string; max_occupants: number }
const initialState: RoomActionState = {};

function useRefreshOnSuccess(success?: boolean) {
  const router = useRouter();
  useEffect(() => { if (success) router.refresh(); }, [router, success]);
}
function Message({ state }: { state: RoomActionState }) {
  if (state.success) return <p className="rounded-lg bg-emerald-50 p-2 text-sm text-emerald-700">บันทึกสำเร็จ</p>;
  if (state.error) return <p role="alert" className="rounded-lg bg-red-50 p-2 text-sm text-red-700">{state.error}</p>;
  return null;
}
function Input({ name, label, type = "text", defaultValue, placeholder, error, required = true }: { name: string; label: string; type?: string; defaultValue?: string | number; placeholder?: string; error?: string; required?: boolean }) {
  return <label className="block text-sm font-medium">{label}<input name={name} type={type} defaultValue={defaultValue} placeholder={placeholder} required={required} className="mt-1.5 w-full rounded-lg border border-slate-300 bg-transparent px-3 py-2.5 outline-none focus:border-teal-600"/><span className="mt-1 block min-h-4 text-xs text-red-600">{error}</span></label>;
}
function SubmitButton({ pending, children }: { pending: boolean; children: React.ReactNode }) { return <button disabled={pending} className="flex w-full items-center justify-center gap-2 rounded-lg bg-teal-700 px-4 py-2.5 font-semibold text-white hover:bg-teal-800 disabled:opacity-60">{pending&&<LoaderCircle size={18} className="animate-spin"/>}{children}</button>; }

export function BuildingForm() {
  const [state, action, pending] = useActionState(createBuildingAction, initialState);
  useRefreshOnSuccess(state.success);
  return <section className="rounded-xl border border-slate-200 bg-[var(--surface)] p-5"><div className="mb-4 flex items-center gap-2"><Building2 className="text-teal-700"/><h2 className="font-bold">1. เพิ่มอาคารและชั้น</h2></div><form action={action} className="space-y-2"><Input name="code" label="รหัสอาคาร" placeholder="A" error={state.fieldErrors?.code?.[0]}/><Input name="name" label="ชื่ออาคาร" placeholder="อาคาร A" error={state.fieldErrors?.name?.[0]}/><Input name="floorCount" label="จำนวนชั้น" type="number" defaultValue={3} error={state.fieldErrors?.floorCount?.[0]}/><Message state={state}/><SubmitButton pending={pending}>สร้างอาคารและชั้น</SubmitButton></form></section>;
}

export function RoomTypeForm() {
  const [state, action, pending] = useActionState(createRoomTypeAction, initialState);
  useRefreshOnSuccess(state.success);
  return <section className="rounded-xl border border-slate-200 bg-[var(--surface)] p-5"><div className="mb-4 flex items-center gap-2"><Layers3 className="text-teal-700"/><h2 className="font-bold">2. เพิ่มประเภทห้อง</h2></div><form action={action} className="space-y-2"><Input name="name" label="ชื่อประเภท" placeholder="ห้องมาตรฐาน" error={state.fieldErrors?.name?.[0]}/><div className="grid grid-cols-2 gap-3"><Input name="baseRent" label="ค่าเช่า/เดือน" defaultValue="4500.00" error={state.fieldErrors?.baseRent?.[0]}/><Input name="deposit" label="เงินประกัน" defaultValue="4500.00" error={state.fieldErrors?.deposit?.[0]}/></div><Input name="maxOccupants" label="ผู้พักสูงสุด" type="number" defaultValue={2} error={state.fieldErrors?.maxOccupants?.[0]}/><Message state={state}/><SubmitButton pending={pending}>บันทึกประเภทห้อง</SubmitButton></form></section>;
}

export function RoomForm({ buildings, roomTypes }: { buildings: BuildingOption[]; roomTypes: RoomTypeOption[] }) {
  const [state, action, pending] = useActionState(createRoomAction, initialState);
  useRefreshOnSuccess(state.success);
  const noReferences = buildings.length === 0 || roomTypes.length === 0;
  return <section className="rounded-xl border border-slate-200 bg-[var(--surface)] p-5"><div className="mb-4 flex items-center gap-2"><DoorOpen className="text-teal-700"/><h2 className="font-bold">3. เพิ่มห้องพัก</h2></div>{noReferences?<div className="rounded-lg bg-amber-50 p-4 text-sm text-amber-800">กรุณาสร้างอาคารและประเภทห้องก่อนเพิ่มห้องพัก</div>:<form action={action} className="grid gap-2 sm:grid-cols-2"><label className="block text-sm font-medium sm:col-span-2">อาคาร / ชั้น<select name="floorId" className="mt-1.5 w-full rounded-lg border border-slate-300 bg-[var(--surface)] px-3 py-2.5">{buildings.map(building=><optgroup key={building.id} label={`${building.code} · ${building.name}`}>{building.floors.map(floor=><option key={floor.id} value={floor.id}>{building.code} · {floor.name ?? `ชั้น ${floor.floor_number}`}</option>)}</optgroup>)}</select></label><label className="block text-sm font-medium sm:col-span-2">ประเภทห้อง<select name="roomTypeId" className="mt-1.5 w-full rounded-lg border border-slate-300 bg-[var(--surface)] px-3 py-2.5">{roomTypes.map(item=><option key={item.id} value={item.id}>{item.name} · ฿{Number(item.base_rent).toLocaleString("th-TH")}</option>)}</select></label><Input name="code" label="รหัสห้อง" placeholder="A101" error={state.fieldErrors?.code?.[0]}/><Input name="roomNumber" label="หมายเลขหน้าห้อง" placeholder="101" error={state.fieldErrors?.roomNumber?.[0]}/><Input name="monthlyRent" label="ค่าเช่าต่อเดือน" defaultValue="4500.00" error={state.fieldErrors?.monthlyRent?.[0]}/><Input name="waterMeterNumber" label="เลขมิเตอร์น้ำ" placeholder="W-A101" required={false}/><Input name="electricMeterNumber" label="เลขมิเตอร์ไฟ" placeholder="E-A101" required={false}/><div className="sm:col-span-2"><Message state={state}/><SubmitButton pending={pending}>เพิ่มห้องพัก</SubmitButton></div></form>}</section>;
}

export type { BuildingOption, RoomTypeOption };
