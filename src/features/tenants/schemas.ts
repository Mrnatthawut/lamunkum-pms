import { z } from "zod";

export function isValidThaiNationalId(value: string): boolean {
  if (!/^\d{13}$/.test(value)) return false;
  const digits = [...value].map(Number);
  const sum = digits.slice(0,12).reduce((total,digit,index)=>total + digit * (13-index),0);
  return (11 - (sum % 11)) % 10 === digits[12];
}

const optionalText = (max: number) => z.string().trim().max(max).optional().default("");
export const createTenantSchema = z.object({
  title: optionalText(30), firstName: z.string().trim().min(1,"กรุณาระบุชื่อ").max(100), lastName: z.string().trim().min(1,"กรุณาระบุนามสกุล").max(100), nickname: optionalText(80),
  phone: z.string().trim().regex(/^[0-9+ -]{9,20}$/,"เบอร์โทรไม่ถูกต้อง"), email: z.union([z.literal(""),z.email("อีเมลไม่ถูกต้อง")]).default(""),
  idType: z.enum(["national_id","passport"]), documentNumber: optionalText(30), birthDate: z.union([z.literal(""),z.iso.date()]).default(""),
  registeredAddress: optionalText(1000), currentAddress: optionalText(1000), occupation: optionalText(120), workplace: optionalText(200), vehicleRegistration: optionalText(50), notes: optionalText(1000),
  emergencyName: optionalText(200), emergencyRelationship: optionalText(100), emergencyPhone: optionalText(20),
}).superRefine((data,ctx)=>{
  if (data.documentNumber && data.idType === "national_id" && !isValidThaiNationalId(data.documentNumber)) ctx.addIssue({code:"custom",path:["documentNumber"],message:"เลขบัตรประชาชนไม่ถูกต้อง"});
  if (data.documentNumber && data.idType === "passport" && !/^[A-Za-z0-9]{5,20}$/.test(data.documentNumber)) ctx.addIssue({code:"custom",path:["documentNumber"],message:"Passport ไม่ถูกต้อง"});
  const hasEmergency = data.emergencyName || data.emergencyRelationship || data.emergencyPhone;
  if (hasEmergency && !(data.emergencyName && data.emergencyRelationship && /^[0-9+ -]{9,20}$/.test(data.emergencyPhone))) ctx.addIssue({code:"custom",path:["emergencyPhone"],message:"กรุณากรอกข้อมูลผู้ติดต่อฉุกเฉินให้ครบ"});
});

export interface TenantActionState { success?: boolean; error?: string; fieldErrors?: Record<string,string[]|undefined> }
