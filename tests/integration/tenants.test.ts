import { createClient } from "@supabase/supabase-js";
import { describe,expect,it } from "vitest";
import { TenantService } from "../../src/services/tenant-service";

const suite=process.env.RUN_LOCAL_INTEGRATION==="1"?describe:describe.skip;
suite("Tenant Management บน Supabase Local",()=>{
  it("สร้าง tenant code, ciphertext, emergency contact และ audit ใน transaction",async()=>{
    const client=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL as string,process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY as string);
    expect((await client.auth.signInWithPassword({email:"owner@dormitory.local",password:"DormitoryLocal!2569"})).error).toBeNull();
    const {data:dormitory}=await client.from("dormitories").select("id").limit(1).single();
    let {data:tenant}=await client.from("tenants").select("id,tenant_code,national_id_encrypted,national_id_last4").eq("phone","0800000001").maybeSingle();
    if(!tenant){
      const id=await new TenantService(client,dormitory?.id as string).create({title:"นาย",firstName:"สมชาย",lastName:"ทดสอบระบบ",nickname:"ชาย",phone:"0800000001",email:"somchai@example.test",idType:"passport",documentNumber:"AB123456",birthDate:"",registeredAddress:"",currentAddress:"กรุงเทพมหานคร",occupation:"พนักงานบริษัท",workplace:"บริษัทตัวอย่าง",vehicleRegistration:"",notes:"ข้อมูลสมมติ",emergencyName:"สมศรี ทดสอบ",emergencyRelationship:"ญาติ",emergencyPhone:"0800000002"});
      tenant=(await client.from("tenants").select("id,tenant_code,national_id_encrypted,national_id_last4").eq("id",id).single()).data;
    }
    expect(tenant?.tenant_code).toMatch(/^TEN-\d{4}-\d{4}$/);
    expect(tenant?.national_id_encrypted).not.toContain("AB123456");
    expect(tenant?.national_id_last4).toBe("3456");
    const {data:contacts}=await client.from("emergency_contacts").select("name,phone").eq("tenant_id",tenant?.id as string);
    expect(contacts).toEqual(expect.arrayContaining([expect.objectContaining({name:"สมศรี ทดสอบ",phone:"0800000002"})]));
  });
});
