import { Bell, Building2, CreditCard, DoorOpen, FileText, Gauge, LayoutDashboard, Megaphone, MessageSquare, ReceiptText, Users, Wrench, type LucideIcon } from "lucide-react";
import { logoutAction } from "@/app/(auth)/login/actions";
import Link from "next/link";

const menus: readonly [LucideIcon,string,string][] = [[LayoutDashboard,"แดชบอร์ด","/"],[Building2,"ห้องพัก","/rooms"],[Users,"ผู้เช่า","/tenants"],[FileText,"สัญญา","/contracts"],[Gauge,"มิเตอร์","/meters"],[ReceiptText,"ใบแจ้งหนี้","/billing"],[CreditCard,"การชำระ","/payments"],[DoorOpen,"ย้ายออก","/move-outs"],[MessageSquare,"LINE Integration","/line"],[MessageSquare,"กล่องข้อความ","/inbox"],[Wrench,"แจ้งซ่อม","/maintenance"],[Megaphone,"ประกาศ","/announcements"]];
export function AppShell({ children }: { children: React.ReactNode }) {
  return <div className="min-h-screen md:grid md:grid-cols-[250px_1fr]">
    <aside className="hidden border-r border-slate-200 bg-[var(--surface)] p-5 md:block"><div className="mb-8 flex items-center gap-3 text-lg font-bold"><span className="grid h-10 w-10 place-items-center rounded-xl bg-teal-700 text-white"><Building2 /></span>ระบบบริหารหอพัก</div><nav className="space-y-1">{menus.map(([Icon,label,href])=><Link key={label} href={href} className="flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-left text-slate-600 hover:bg-slate-100 hover:text-teal-800"><Icon size={19}/>{label}</Link>)}</nav></aside>
    <main><header className="flex h-16 items-center justify-between border-b border-slate-200 bg-[var(--surface)] px-4 md:px-8"><div><p className="text-xs text-[var(--muted)]">ระบบบริหารหอพัก</p><p className="font-semibold">Dormitory Management System</p></div><div className="flex items-center gap-2"><Link href="/notifications" aria-label="การแจ้งเตือน" className="relative rounded-full p-2"><Bell/><span className="absolute right-1 top-1 h-2 w-2 rounded-full bg-red-500"/></Link><form action={logoutAction}><button className="rounded-lg border border-slate-300 px-3 py-2 text-sm">ออกจากระบบ</button></form></div></header>{children}</main>
  </div>;
}
