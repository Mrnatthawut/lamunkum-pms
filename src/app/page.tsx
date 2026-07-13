import { AppShell } from "@/components/app-shell";
import { AlertTriangle, Banknote, BedDouble, CheckCircle2, Clock3, DoorOpen } from "lucide-react";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import { SetupOrganizationForm } from "@/components/setup-organization-form";

export default async function DashboardPage() {
 const supabase = await createSupabaseServerClient();
 if (!supabase) return <SetupOrganizationForm/>;
 const { data: { user } } = await supabase.auth.getUser();
 if (!user) redirect("/login");
 const { data: membership } = await supabase.from("organization_members").select("organization_id,role").eq("profile_id", user.id).eq("active", true).maybeSingle();
 if (!membership) return <SetupOrganizationForm/>;
 const { data: rooms = [] } = supabase ? await supabase.from("rooms").select("id,room_number,status,monthly_rent").is("deleted_at", null).order("room_number").limit(30) : { data: [] };
 const total = rooms?.length ?? 0;
 const vacant = rooms?.filter((room) => room.status === "vacant").length ?? 0;
 const occupied = rooms?.filter((room) => room.status === "occupied").length ?? 0;
 const stats = [[BedDouble,"ห้องทั้งหมด",String(total),""],[DoorOpen,"ห้องว่าง",String(vacant),"text-emerald-600"],[CheckCircle2,"อัตราเข้าพัก",total ? `${Math.round(occupied/total*100)}%` : "—","text-teal-600"],[Banknote,"ยอดรับเดือนนี้","—","text-emerald-600"],[AlertTriangle,"ยอดค้างชำระ","—","text-red-600"],[Clock3,"รอตรวจสอบ","—","text-orange-600"]] as const;
 return <AppShell><div className="mx-auto max-w-7xl p-4 md:p-8"><div className="mb-6"><h1 className="text-2xl font-bold">ภาพรวมวันนี้</h1><p className="text-sm text-[var(--muted)]">ข้อมูลจริงตามสิทธิ์ของบัญชีที่เข้าสู่ระบบ</p></div><section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-6">{stats.map(([Icon,label,value,color])=><article key={label} className="rounded-xl border border-slate-200 bg-[var(--surface)] p-4 shadow-sm"><Icon className="mb-4 text-teal-700" size={21}/><p className="text-sm text-[var(--muted)]">{label}</p><p className={`mt-1 text-2xl font-bold ${color}`}>{value}</p></article>)}</section><section className="mt-8"><div className="mb-4 flex items-end justify-between"><div><h2 className="text-xl font-bold">Monitor ห้องพัก</h2><p className="text-sm text-[var(--muted)]">อัปเดตจากฐานข้อมูล</p></div></div>{!rooms?.length?<div className="rounded-xl border border-dashed border-slate-300 p-10 text-center text-[var(--muted)]">ยังไม่มีข้อมูลห้อง หรือยังไม่ได้ตั้งค่า Supabase</div>:<div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">{rooms.map(room=><article key={room.id} className="rounded-xl border border-l-4 border-l-teal-600 bg-[var(--surface)] p-4 shadow-sm"><div className="flex justify-between"><p className="text-xl font-bold">{room.room_number}</p><span className="rounded-full bg-slate-100 px-2 py-1 text-xs text-slate-700">{room.status}</span></div><p className="mt-4 text-sm">ค่าเช่า ฿{Number(room.monthly_rent).toLocaleString("th-TH")}</p></article>)}</div>}</section></div></AppShell>;
}
