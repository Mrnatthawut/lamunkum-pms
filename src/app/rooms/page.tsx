import { AppShell } from "@/components/app-shell";
import { BuildingForm, RoomForm, RoomTypeForm, type BuildingOption, type RoomTypeOption } from "@/components/rooms/room-management";
import { requireDormitoryContext } from "@/lib/auth/context";

function relationName(value: { name: string | null } | Array<{ name: string | null }> | null): string {
  if (Array.isArray(value)) return value[0]?.name ?? "—";
  return value?.name ?? "—";
}

export default async function RoomsPage() {
  const context = await requireDormitoryContext("rooms.read");
  const [{ data: buildings }, { data: roomTypes }, { data: rooms }] = await Promise.all([
    context.supabase.from("buildings").select("id,code,name,floors(id,floor_number,name)").eq("dormitory_id", context.dormitoryId).order("code"),
    context.supabase.from("room_types").select("id,name,base_rent,deposit,max_occupants").eq("dormitory_id", context.dormitoryId).order("name"),
    context.supabase.from("rooms").select("id,room_number,code,status,monthly_rent,buildings(name),floors(name),room_types(name)").eq("dormitory_id", context.dormitoryId).is("deleted_at", null).order("room_number"),
  ]);
  return <AppShell><div className="mx-auto max-w-7xl p-4 md:p-8"><header className="mb-6"><p className="text-sm font-semibold text-teal-700">SETUP โครงสร้างหอพัก</p><h1 className="text-2xl font-bold">อาคาร ชั้น และห้องพัก</h1><p className="text-sm text-[var(--muted)]">{context.dormitoryName} · สร้างตามลำดับจากซ้ายไปขวา</p></header><div className="grid gap-4 xl:grid-cols-3"><BuildingForm/><RoomTypeForm/><RoomForm buildings={(buildings ?? []) as BuildingOption[]} roomTypes={(roomTypes ?? []) as RoomTypeOption[]}/></div><section className="mt-8"><div className="mb-3 flex items-end justify-between"><div><h2 className="text-xl font-bold">ห้องพักทั้งหมด</h2><p className="text-sm text-[var(--muted)]">{rooms?.length ?? 0} ห้อง</p></div></div>{!rooms?.length?<div className="rounded-xl border border-dashed border-slate-300 p-10 text-center text-[var(--muted)]">ยังไม่มีห้องพัก ใช้แบบฟอร์มด้านบนเพื่อเพิ่มห้องแรก</div>:<div className="overflow-x-auto rounded-xl border border-slate-200 bg-[var(--surface)]"><table className="w-full min-w-[720px] text-left text-sm"><thead className="border-b border-slate-200 bg-slate-50 text-slate-600"><tr><th className="p-3">ห้อง</th><th className="p-3">อาคาร/ชั้น</th><th className="p-3">ประเภท</th><th className="p-3">ค่าเช่า</th><th className="p-3">สถานะ</th></tr></thead><tbody>{rooms.map(room=><tr key={room.id} className="border-b border-slate-100 last:border-0"><td className="p-3 font-semibold">{room.room_number}<span className="ml-2 text-xs text-[var(--muted)]">{room.code}</span></td><td className="p-3">{relationName(room.buildings)} · {relationName(room.floors)}</td><td className="p-3">{relationName(room.room_types)}</td><td className="p-3">฿{Number(room.monthly_rent).toLocaleString("th-TH")}</td><td className="p-3"><span className="rounded-full bg-emerald-50 px-2 py-1 text-xs text-emerald-700">{room.status}</span></td></tr>)}</tbody></table></div>}</section></div></AppShell>;
}
