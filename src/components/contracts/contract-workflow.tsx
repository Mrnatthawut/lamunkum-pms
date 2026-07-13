"use client";

import { useActionState, useEffect, useRef, useState } from "react";
import { CalendarCheck, FileSignature, LoaderCircle } from "lucide-react";
import { useRouter } from "next/navigation";
import { createContractAction, createReservationAction } from "@/app/contracts/actions";
import type { ContractActionState } from "@/features/contracts/schemas";

interface RoomOption { id: string; roomNumber: string; monthlyRent: string; deposit: string; status: string }
interface TenantOption { id: string; label: string }
interface ReservationOption { id: string; label: string; roomId: string; tenantId: string }
interface Props { rooms: RoomOption[]; tenants: TenantOption[]; confirmedReservations: ReservationOption[] }
const initialState: ContractActionState = {};
const fieldClass = "mt-1.5 w-full rounded-lg border border-slate-300 bg-[var(--surface)] px-3 py-2.5 outline-none focus:border-teal-600";

function FieldError({ value }: { value?: string }) { return <span className="mt-1 block min-h-4 text-xs text-red-600">{value}</span>; }

export function ContractWorkflow({ rooms, tenants, confirmedReservations }: Props) {
  const [reservationState, reservationAction, reservationPending] = useActionState(createReservationAction, initialState);
  const [contractState, contractAction, contractPending] = useActionState(createContractAction, initialState);
  const reservationForm = useRef<HTMLFormElement>(null);
  const contractForm = useRef<HTMLFormElement>(null);
  const router = useRouter();
  const [reservationId, setReservationId] = useState("");
  const [roomId, setRoomId] = useState("");
  const [tenantId, setTenantId] = useState("");
  useEffect(() => { if (reservationState.success) { reservationForm.current?.reset(); router.refresh(); } }, [reservationState.success, router]);
  useEffect(() => { if (contractState.success) { contractForm.current?.reset(); router.refresh(); } }, [contractState.success, router]);
  const [defaults] = useState(() => {
    const now = new Date();
    const todayValue = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Bangkok", year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
    return { today: todayValue, nextYear: `${Number(todayValue.slice(0, 4)) + 1}${todayValue.slice(4)}`, tomorrow: new Date(now.getTime() + 86400000).toISOString().slice(0, 16) };
  });
  const rError = (name: string) => reservationState.fieldErrors?.[name]?.[0];
  const cError = (name: string) => contractState.fieldErrors?.[name]?.[0];
  const chooseReservation = (id: string) => {
    setReservationId(id);
    const selected = confirmedReservations.find((item) => item.id === id);
    if (selected) { setRoomId(selected.roomId); setTenantId(selected.tenantId); }
  };

  return <div className="grid items-start gap-5 xl:grid-cols-2">
    <section className="rounded-xl border border-slate-200 bg-[var(--surface)] p-5">
      <div className="mb-5 flex items-center gap-2"><CalendarCheck className="text-blue-700"/><div><h2 className="font-bold">1. สร้างการจอง</h2><p className="text-xs text-[var(--muted)]">ใช้ได้เฉพาะห้องว่าง และหนึ่งห้องมีการจองเปิดอยู่ได้หนึ่งรายการ</p></div></div>
      <form ref={reservationForm} action={reservationAction} className="space-y-3">
        <div className="grid gap-3 sm:grid-cols-2"><label className="text-sm font-medium">ห้องว่าง<select name="roomId" required className={fieldClass}><option value="">เลือกห้อง</option>{rooms.filter((room) => room.status === "vacant").map((room) => <option key={room.id} value={room.id}>ห้อง {room.roomNumber} · ฿{Number(room.monthlyRent).toLocaleString("th-TH")}</option>)}</select><FieldError value={rError("roomId")}/></label><label className="text-sm font-medium">ผู้เช่า<select name="tenantId" required className={fieldClass}><option value="">เลือกผู้เช่า</option>{tenants.map((tenant) => <option key={tenant.id} value={tenant.id}>{tenant.label}</option>)}</select><FieldError value={rError("tenantId")}/></label></div>
        <div className="grid gap-3 sm:grid-cols-2"><label className="text-sm font-medium">วันที่คาดว่าจะเข้าอยู่<input name="expectedMoveInDate" type="date" min={defaults.today} defaultValue={defaults.today} required className={fieldClass}/><FieldError value={rError("expectedMoveInDate")}/></label><label className="text-sm font-medium">หมดอายุการจอง<input name="expiresAt" type="datetime-local" defaultValue={defaults.tomorrow} required className={fieldClass}/><FieldError value={rError("expiresAt")}/></label></div>
        <div className="grid gap-3 sm:grid-cols-3"><label className="text-sm font-medium">เงินจอง (บาท)<input name="bookingAmount" inputMode="decimal" defaultValue="0.00" required className={fieldClass}/><FieldError value={rError("bookingAmount")}/></label><label className="text-sm font-medium">ช่องทางชำระ<select name="paymentMethod" className={fieldClass}><option value="">ยังไม่ชำระ</option><option value="cash">เงินสด</option><option value="bank_transfer">โอนธนาคาร</option><option value="promptpay">PromptPay</option></select><FieldError value={rError("paymentMethod")}/></label><label className="text-sm font-medium">สถานะ<select name="status" className={fieldClass}><option value="pending_payment">รอชำระเงินจอง</option><option value="confirmed">ยืนยันแล้ว</option></select></label></div>
        <label className="block text-sm font-medium">หมายเหตุ<textarea name="notes" rows={2} className={fieldClass}/></label>
        {reservationState.error && <p role="alert" className="rounded-lg bg-red-50 p-3 text-sm text-red-700">{reservationState.error}</p>}{reservationState.success && <p className="rounded-lg bg-emerald-50 p-3 text-sm text-emerald-700">{reservationState.message}</p>}
        <button disabled={reservationPending || !rooms.some((room) => room.status === "vacant")} className="flex w-full items-center justify-center gap-2 rounded-lg bg-blue-700 px-4 py-2.5 font-semibold text-white disabled:opacity-50">{reservationPending && <LoaderCircle size={18} className="animate-spin"/>}บันทึกการจอง</button>
      </form>
    </section>

    <section className="rounded-xl border border-slate-200 bg-[var(--surface)] p-5">
      <div className="mb-5 flex items-center gap-2"><FileSignature className="text-teal-700"/><div><h2 className="font-bold">2. สร้างสัญญาและย้ายเข้า</h2><p className="text-xs text-[var(--muted)]">เลือกการจองที่ยืนยันแล้ว หรือทำสัญญาจากห้องว่างโดยตรง</p></div></div>
      <form ref={contractForm} action={contractAction} className="space-y-3">
        <label className="block text-sm font-medium">อ้างอิงการจอง (ถ้ามี)<select name="reservationId" value={reservationId} onChange={(event) => chooseReservation(event.target.value)} className={fieldClass}><option value="">ไม่อ้างอิง — ย้ายเข้าโดยตรง</option>{confirmedReservations.map((item) => <option key={item.id} value={item.id}>{item.label}</option>)}</select></label>
        <div className="grid gap-3 sm:grid-cols-2"><label className="text-sm font-medium">ห้อง<select name="roomId" value={roomId} onChange={(event) => setRoomId(event.target.value)} required className={fieldClass}><option value="">เลือกห้อง</option>{rooms.map((room) => <option key={room.id} value={room.id} disabled={room.status !== "vacant" && !confirmedReservations.some((item) => item.id === reservationId && item.roomId === room.id)}>ห้อง {room.roomNumber} · {room.status === "reserved" ? "จองแล้ว" : "ว่าง"}</option>)}</select><FieldError value={cError("roomId")}/></label><label className="text-sm font-medium">ผู้เช่า<select name="tenantId" value={tenantId} onChange={(event) => setTenantId(event.target.value)} required className={fieldClass}><option value="">เลือกผู้เช่า</option>{tenants.map((tenant) => <option key={tenant.id} value={tenant.id}>{tenant.label}</option>)}</select><FieldError value={cError("tenantId")}/></label></div>
        <div className="grid gap-3 sm:grid-cols-3"><label className="text-sm font-medium">วันที่ทำสัญญา<input name="contractDate" type="date" defaultValue={defaults.today} required className={fieldClass}/><FieldError value={cError("contractDate")}/></label><label className="text-sm font-medium">เริ่มสัญญา<input name="startDate" type="date" defaultValue={defaults.today} required className={fieldClass}/><FieldError value={cError("startDate")}/></label><label className="text-sm font-medium">สิ้นสุดสัญญา<input name="endDate" type="date" defaultValue={defaults.nextYear} required className={fieldClass}/><FieldError value={cError("endDate")}/></label></div>
        <div className="grid gap-3 sm:grid-cols-3"><label className="text-sm font-medium">ค่าเช่า/เดือน<input name="monthlyRent" inputMode="decimal" defaultValue="4500.00" required className={fieldClass}/><FieldError value={cError("monthlyRent")}/></label><label className="text-sm font-medium">เงินประกันตามสัญญา<input name="deposit" inputMode="decimal" defaultValue="4500.00" required className={fieldClass}/><FieldError value={cError("deposit")}/></label><label className="text-sm font-medium">ค่าเช่าล่วงหน้า<input name="advanceRent" inputMode="decimal" defaultValue="0.00" required className={fieldClass}/><FieldError value={cError("advanceRent")}/></label></div>
        <div className="grid gap-3 sm:grid-cols-2"><label className="text-sm font-medium">ครบกำหนดชำระวันที่<input name="dueDay" type="number" min="1" max="28" defaultValue="5" required className={fieldClass}/></label><label className="text-sm font-medium">แจ้งย้ายออกล่วงหน้า (วัน)<input name="noticeDays" type="number" min="0" defaultValue="30" required className={fieldClass}/></label></div>
        <div className="grid gap-3 sm:grid-cols-2"><label className="text-sm font-medium">มิเตอร์น้ำเริ่มต้น<input name="initialWater" inputMode="decimal" defaultValue="0.000" required className={fieldClass}/><FieldError value={cError("initialWater")}/></label><label className="text-sm font-medium">มิเตอร์ไฟเริ่มต้น<input name="initialElectric" inputMode="decimal" defaultValue="0.000" required className={fieldClass}/><FieldError value={cError("initialElectric")}/></label></div>
        <label className="block text-sm font-medium">ผลตรวจสภาพห้อง<textarea name="inspectionNotes" rows={2} placeholder="พื้น ผนัง ประตู หน้าต่าง ห้องน้ำ และทรัพย์สิน" className={fieldClass}/></label><label className="block text-sm font-medium">หมายเหตุสัญญา<textarea name="notes" rows={2} className={fieldClass}/></label>
        <p className="text-xs text-amber-700">เงินประกันในหน้านี้เป็นเงื่อนไขตามสัญญา ยังไม่ถือว่าได้รับเงินจริงจนกว่าจะบันทึกและยืนยันในระบบชำระเงิน</p>
        {contractState.error && <p role="alert" className="rounded-lg bg-red-50 p-3 text-sm text-red-700">{contractState.error}</p>}{contractState.success && <p className="rounded-lg bg-emerald-50 p-3 text-sm text-emerald-700">{contractState.message}</p>}
        <button disabled={contractPending} className="flex w-full items-center justify-center gap-2 rounded-lg bg-teal-700 px-4 py-2.5 font-semibold text-white disabled:opacity-50">{contractPending && <LoaderCircle size={18} className="animate-spin"/>}สร้างสัญญาและย้ายเข้า</button>
      </form>
    </section>
  </div>;
}
