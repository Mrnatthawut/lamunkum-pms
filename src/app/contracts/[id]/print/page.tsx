import { notFound } from "next/navigation";
import { PrintButton } from "@/components/documents/print-button";
import { requireDormitoryContext } from "@/lib/auth/context";
import { relationOne } from "@/lib/supabase/relations";

const thaiDate = (value: string) => new Intl.DateTimeFormat("th-TH", { dateStyle: "long", timeZone: "Asia/Bangkok" }).format(new Date(value));
const money = (value: string | number) => new Intl.NumberFormat("th-TH", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(Number(value));

export default async function ContractPrintPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const context = await requireDormitoryContext("contracts.manage");
  const [{ data: contract }, { data: dormitory }, { data: organization }] = await Promise.all([
    context.supabase.from("contracts").select("id,contract_number,contract_date,start_date,end_date,monthly_rent,deposit,advance_rent,due_day,notice_days,notes,rooms(room_number),tenants(title,first_name,last_name,phone,current_address)").eq("id", id).eq("dormitory_id", context.dormitoryId).single(),
    context.supabase.from("dormitories").select("name,address,phone").eq("id", context.dormitoryId).single(),
    context.supabase.from("organizations").select("name,tax_id,address,phone").eq("id", context.organizationId).single(),
  ]);
  if (!contract || !dormitory || !organization) notFound();
  const { data: moveIn } = await context.supabase.from("move_ins").select("initial_water_reading,initial_electric_reading,inspection_notes").eq("contract_id", contract.id).single();
  const tenant = relationOne(contract.tenants);
  const room = relationOne(contract.rooms);
  const tenantName = `${tenant?.title ?? ""}${tenant?.first_name ?? ""} ${tenant?.last_name ?? ""}`.trim();
  return <main className="contract-document mx-auto my-6 min-h-[297mm] w-[210mm] bg-white p-[20mm] text-[14px] leading-7 text-slate-900 shadow-xl print:my-0 print:shadow-none">
    <div className="print-hidden mb-5 flex justify-end"><PrintButton/></div>
    <header className="mb-7 text-center"><h1 className="text-2xl font-bold">สัญญาเช่าห้องพัก</h1><p>เลขที่สัญญา {contract.contract_number}</p></header>
    <p className="text-right">ทำ ณ {dormitory.name}<br/>วันที่ {thaiDate(contract.contract_date)}</p>
    <p className="mt-5 indent-10">สัญญาฉบับนี้ทำขึ้นระหว่าง <strong>{organization.name}</strong> ที่อยู่ {organization.address || dormitory.address} โทรศัพท์ {organization.phone || dormitory.phone || "—"} ซึ่งต่อไปเรียกว่า “ผู้ให้เช่า” ฝ่ายหนึ่ง กับ <strong>{tenantName}</strong> ที่อยู่ {tenant?.current_address || "ตามข้อมูลผู้เช่าในระบบ"} โทรศัพท์ {tenant?.phone || "—"} ซึ่งต่อไปเรียกว่า “ผู้เช่า” อีกฝ่ายหนึ่ง</p>
    <h2 className="mt-5 font-bold">ข้อ 1 ทรัพย์สินที่เช่าและระยะเวลา</h2><p className="indent-10">ผู้ให้เช่าตกลงให้เช่าและผู้เช่าตกลงเช่าห้องพักเลขที่ <strong>{room?.room_number}</strong> ณ {dormitory.name} ตั้งแต่วันที่ {thaiDate(contract.start_date)} ถึงวันที่ {thaiDate(contract.end_date)}</p>
    <h2 className="mt-4 font-bold">ข้อ 2 ค่าเช่าและการชำระ</h2><p className="indent-10">ค่าเช่าเดือนละ <strong>{money(contract.monthly_rent)} บาท</strong> กำหนดชำระภายในวันที่ {contract.due_day} ของทุกเดือน ค่าเช่าล่วงหน้า {money(contract.advance_rent)} บาท</p>
    <h2 className="mt-4 font-bold">ข้อ 3 เงินประกัน</h2><p className="indent-10">เงินประกันตามสัญญาจำนวน <strong>{money(contract.deposit)} บาท</strong> การรับเงินจริงและการคืนเงินให้ยึดตามใบรับเงิน รายการบัญชี และเงื่อนไขการหักค่าเสียหายของหอพัก</p>
    <h2 className="mt-4 font-bold">ข้อ 4 การย้ายออก</h2><p className="indent-10">ผู้เช่าต้องแจ้งย้ายออกล่วงหน้าไม่น้อยกว่า {contract.notice_days} วัน และชำระยอดค้าง ค่าใช้จ่ายสุดท้าย รวมถึงค่าเสียหายที่ตรวจพบก่อนสิ้นสุดสัญญา</p>
    <h2 className="mt-4 font-bold">ข้อ 5 ค่ามิเตอร์เริ่มต้นและสภาพห้อง</h2><p className="indent-10">มิเตอร์น้ำเริ่มต้น {moveIn?.initial_water_reading ?? "0.000"} หน่วย มิเตอร์ไฟเริ่มต้น {moveIn?.initial_electric_reading ?? "0.000"} หน่วย</p><p className="whitespace-pre-wrap rounded border border-slate-300 p-3">{moveIn?.inspection_notes || "ไม่พบหมายเหตุเพิ่มเติม"}</p>
    {contract.notes && <><h2 className="mt-4 font-bold">เงื่อนไขเพิ่มเติม</h2><p className="whitespace-pre-wrap indent-10">{contract.notes}</p></>}
    <p className="mt-5 indent-10">คู่สัญญาได้อ่านและเข้าใจข้อความโดยตลอดแล้ว จึงลงลายมือชื่อไว้เป็นหลักฐาน ทั้งนี้ควรให้ผู้เชี่ยวชาญกฎหมายไทยตรวจสอบแบบสัญญาและการลงนามอิเล็กทรอนิกส์ก่อนนำไปใช้เป็นหลักฐานจริง</p>
    <div className="mt-16 grid grid-cols-2 gap-16 text-center"><div><div className="mb-3 border-b border-slate-700"/><p>ผู้ให้เช่า</p><p>วันที่ ______ / ______ / ______</p></div><div><div className="mb-3 border-b border-slate-700"/><p>ผู้เช่า ({tenantName})</p><p>วันที่ ______ / ______ / ______</p></div></div>
    <footer className="mt-14 border-t pt-3 text-center text-xs text-slate-500">เอกสารสร้างจาก Dormitory Management System · {contract.contract_number}</footer>
  </main>;
}
