"use client";

import { useActionState } from "react";
import { FilePlus2, LoaderCircle } from "lucide-react";
import { createContractTemplateVersionAction } from "@/app/contracts/actions";
import { allowedContractVariables } from "@/features/contracts/template-schemas";
import type { ContractActionState } from "@/features/contracts/schemas";

export function TemplateEditor({ name, body }: { name: string; body: string }) {
  const [state, action, pending] = useActionState<ContractActionState, FormData>(createContractTemplateVersionAction, {});
  return <form action={action} className="space-y-4 rounded-xl border border-slate-200 bg-[var(--surface)] p-5"><div className="flex items-center gap-2"><FilePlus2 className="text-teal-700"/><div><h2 className="font-bold">สร้าง Version ใหม่</h2><p className="text-xs text-[var(--muted)]">Version เดิมและ PDF ที่สร้างแล้วจะไม่ถูกแก้ไข</p></div></div><label className="block text-sm font-medium">ชื่อ Template<input name="name" defaultValue={name} required className="mt-1.5 w-full rounded-lg border border-slate-300 bg-transparent px-3 py-2.5"/><span className="text-xs text-red-600">{state.fieldErrors?.name?.[0]}</span></label><label className="block text-sm font-medium">ข้อความสัญญา<textarea name="body" defaultValue={body} required rows={24} className="mt-1.5 w-full rounded-lg border border-slate-300 bg-transparent px-3 py-2.5 font-mono text-sm leading-6"/><span className="text-xs text-red-600">{state.fieldErrors?.body?.[0]}</span></label><details className="rounded-lg border border-slate-200 p-3"><summary className="cursor-pointer text-sm font-semibold">ตัวแปรที่รองรับ</summary><div className="mt-3 flex flex-wrap gap-2">{allowedContractVariables.map((item) => <code key={item} className="rounded bg-slate-100 px-2 py-1 text-xs">{`{{${item}}}`}</code>)}</div></details>{state.error && <p role="alert" className="rounded-lg bg-red-50 p-3 text-sm text-red-700">{state.error}</p>}{state.success && <p className="rounded-lg bg-emerald-50 p-3 text-sm text-emerald-700">{state.message}</p>}<button disabled={pending} className="flex items-center gap-2 rounded-lg bg-teal-700 px-4 py-2.5 font-semibold text-white disabled:opacity-50">{pending && <LoaderCircle size={18} className="animate-spin"/>}บันทึกเป็น Version ใหม่</button></form>;
}
