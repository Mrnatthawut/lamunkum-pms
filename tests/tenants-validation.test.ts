import { describe, expect, it } from "vitest";
import { createTenantSchema, isValidThaiNationalId } from "../src/features/tenants/schemas";

function makeNationalId(first12: string) { const sum=[...first12].map(Number).reduce((total,digit,index)=>total+digit*(13-index),0); return `${first12}${(11-(sum%11))%10}`; }
describe("Tenant validation",()=>{
  it("ตรวจ checksum เลขบัตรประชาชน",()=>{const id=makeNationalId("123456789012");expect(isValidThaiNationalId(id)).toBe(true);expect(isValidThaiNationalId(`${id.slice(0,12)}${(Number(id[12])+1)%10}`)).toBe(false);});
  it("รับผู้เช่าที่มี Passport",()=>expect(createTenantSchema.safeParse({title:"นาย",firstName:"สมชาย",lastName:"ทดสอบ",nickname:"",phone:"0800000001",email:"",idType:"passport",documentNumber:"AB123456",birthDate:"",registeredAddress:"",currentAddress:"",occupation:"",workplace:"",vehicleRegistration:"",notes:"",emergencyName:"",emergencyRelationship:"",emergencyPhone:""}).success).toBe(true));
  it("บังคับข้อมูลผู้ติดต่อฉุกเฉินให้ครบชุด",()=>expect(createTenantSchema.safeParse({title:"",firstName:"สมชาย",lastName:"ทดสอบ",nickname:"",phone:"0800000001",email:"",idType:"national_id",documentNumber:"",birthDate:"",registeredAddress:"",currentAddress:"",occupation:"",workplace:"",vehicleRegistration:"",notes:"",emergencyName:"ญาติ",emergencyRelationship:"",emergencyPhone:""}).success).toBe(false));
});
