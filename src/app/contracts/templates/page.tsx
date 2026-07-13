import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { AppShell } from "@/components/app-shell";
import { TemplateEditor } from "@/components/contracts/template-editor";
import { requireDormitoryContext } from "@/lib/auth/context";

export default async function ContractTemplatesPage() {
  const context = await requireDormitoryContext("contracts.manage");
  const { data: template } = await context.supabase.from("contract_templates").select("id,name,current_version_id").eq("dormitory_id", context.dormitoryId).eq("code", "lease_contract").single();
  const { data: versions } = template ? await context.supabase.from("contract_versions").select("id,version_number,body,checksum,created_at").eq("template_id", template.id).order("version_number", { ascending: false }) : { data: [] };
  const current = versions?.find((item) => item.id === template?.current_version_id) ?? versions?.[0];
  return <AppShell><div className="mx-auto max-w-5xl p-4 md:p-8"><Link href="/contracts" className="mb-5 inline-flex items-center gap-1 text-sm text-teal-700"><ArrowLeft size={16}/>กลับหน้าสัญญา</Link><header className="mb-6"><p className="text-sm font-semibold text-teal-700">CONTRACT TEMPLATE</p><h1 className="text-2xl font-bold">Template สัญญาเช่า</h1><p className="text-sm text-[var(--muted)]">{context.dormitoryName} · เอกสารที่สร้างแล้วจะเก็บ Snapshot และ Checksum ของ Version</p></header>{current ? <TemplateEditor name={template?.name ?? "สัญญาเช่ามาตรฐาน"} body={current.body}/> : <div className="rounded-xl bg-red-50 p-5 text-red-700">ไม่พบ Template เริ่มต้น กรุณาตรวจสอบ Migration</div>}<section className="mt-5 rounded-xl border border-slate-200 bg-[var(--surface)]"><h2 className="border-b p-4 font-bold">ประวัติ Version</h2><div className="divide-y">{versions?.map((item) => <div key={item.id} className="flex items-center justify-between gap-4 p-4"><div><p className="font-semibold">Version {item.version_number}{item.id === template?.current_version_id && <span className="ml-2 rounded-full bg-emerald-50 px-2 py-0.5 text-xs text-emerald-700">ใช้งานปัจจุบัน</span>}</p><p className="text-xs text-[var(--muted)]">{new Intl.DateTimeFormat("th-TH", { dateStyle: "medium", timeStyle: "short", timeZone: "Asia/Bangkok" }).format(new Date(item.created_at))}</p></div><code className="text-xs text-slate-500">SHA-256 {item.checksum.slice(0, 16)}…</code></div>)}</div></section></div></AppShell>;
}
