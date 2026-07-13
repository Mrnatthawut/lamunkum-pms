"use client";

import { useActionState } from "react";
import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { Building2, LoaderCircle } from "lucide-react";
import { bootstrapOrganizationAction } from "@/features/organizations/bootstrap-actions";

export function SetupOrganizationForm() {
  const router = useRouter();
  const [state, action, pending] = useActionState(bootstrapOrganizationAction, {});
  useEffect(() => { if (state.success) router.refresh(); }, [router, state.success]);
  const field = (name: string) => state.fieldErrors?.[name]?.[0];
  return <main className="grid min-h-[calc(100vh-4rem)] place-items-center p-4"><section className="w-full max-w-xl rounded-2xl border border-slate-200 bg-[var(--surface)] p-7 shadow-sm"><div className="mb-6 flex gap-3"><span className="grid h-11 w-11 shrink-0 place-items-center rounded-xl bg-teal-700 text-white"><Building2/></span><div><p className="text-xs font-semibold text-teal-700">SETUP 1/12</p><h1 className="text-xl font-bold">ตั้งค่ากิจการและหอพักแรก</h1></div></div><form action={action} className="grid gap-4 sm:grid-cols-2"><Field name="organizationName" label="ชื่อกิจการ" error={field("organizationName")}/><Field name="dormitoryName" label="ชื่อหอพัก" error={field("dormitoryName")}/><Field name="dormitoryCode" label="รหัสหอพัก" placeholder="BANSUKJAI" error={field("dormitoryCode")}/><div className="sm:col-span-2"><Field name="dormitoryAddress" label="ที่อยู่หอพัก" error={field("dormitoryAddress")}/></div>{state.error&&<p role="alert" className="sm:col-span-2 rounded-lg bg-red-50 p-3 text-sm text-red-700">{state.error}</p>}<button disabled={pending} className="sm:col-span-2 flex items-center justify-center gap-2 rounded-lg bg-teal-700 px-4 py-2.5 font-semibold text-white disabled:opacity-60">{pending&&<LoaderCircle size={18} className="animate-spin"/>}บันทึกและเริ่มใช้งาน</button></form></section></main>;
}
function Field({ name, label, placeholder, error }: { name: string; label: string; placeholder?: string; error?: string }) { return <label className="block text-sm font-medium">{label}<input name={name} placeholder={placeholder} required className="mt-1.5 w-full rounded-lg border border-slate-300 bg-transparent px-3 py-2.5 outline-none focus:border-teal-600"/><span className="mt-1 block text-xs text-red-600">{error}</span></label>; }
