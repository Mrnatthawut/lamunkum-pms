import { createThaiContractPdf } from "@/lib/documents/pdf";
import { renderContractTemplate } from "@/lib/documents/template";
import { requireDormitoryContext } from "@/lib/auth/context";

export const runtime = "nodejs";

export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params; const context = await requireDormitoryContext("contracts.manage");
    const { data, error } = await context.supabase.from("generated_documents").select("template_snapshot,data_snapshot,checksum").eq("id", id).eq("dormitory_id", context.dormitoryId).eq("document_type", "contract").single();
    if (error || !data || typeof data.data_snapshot !== "object" || !data.data_snapshot || Array.isArray(data.data_snapshot)) return new Response("Not found", { status: 404 });
    const snapshot = data.data_snapshot as Record<string, unknown>;
    const contractNumber = typeof snapshot.contract_number === "string" ? snapshot.contract_number : "CONTRACT";
    const content = renderContractTemplate(data.template_snapshot, snapshot);
    const { data: signatureRows } = await context.supabase.from("contract_signatures").select("signer_role,signer_name,signed_at,mime_type,storage_path").eq("generated_document_id", id).order("signed_at");
    const signatures = (await Promise.all((signatureRows ?? []).map(async (signature) => {
      const downloaded = await context.supabase.storage.from("contract-signatures").download(signature.storage_path);
      if (downloaded.error) return null;
      return { signerRole: signature.signer_role, signerName: signature.signer_name, signedAt: signature.signed_at, mimeType: signature.mime_type, bytes: new Uint8Array(await downloaded.data.arrayBuffer()) };
    }))).filter((signature): signature is NonNullable<typeof signature> => signature !== null);
    const bytes = await createThaiContractPdf(content, contractNumber, data.checksum, signatures);
    const body = Uint8Array.from(bytes).buffer;
    return new Response(body, { headers: { "Content-Type": "application/pdf", "Content-Disposition": `attachment; filename="${contractNumber}.pdf"`, "Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff" } });
  } catch { return new Response("Unauthorized", { status: 401 }); }
}
