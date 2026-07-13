import { Building2, ShieldCheck } from "lucide-react";
import { LoginForm } from "./login-form";

export default function LoginPage() {
  return <main className="grid min-h-screen place-items-center p-4"><section className="w-full max-w-md rounded-2xl border border-slate-200 bg-[var(--surface)] p-7 shadow-xl shadow-slate-200/40"><div className="mb-7"><span className="mb-4 grid h-12 w-12 place-items-center rounded-xl bg-teal-700 text-white"><Building2/></span><h1 className="text-2xl font-bold">เข้าสู่ระบบบริหารหอพัก</h1><p className="mt-1 text-sm text-[var(--muted)]">ใช้บัญชีที่ผู้ดูแลกิจการเชิญเข้าสู่ระบบ</p></div><LoginForm/><div className="mt-6 flex items-start gap-2 border-t border-slate-200 pt-5 text-xs text-[var(--muted)]"><ShieldCheck size={17} className="shrink-0 text-teal-700"/><p>ระบบตรวจสอบ session และสิทธิ์ซ้ำที่ Server และ PostgreSQL RLS ทุกครั้ง</p></div></section></main>;
}
