import { createClient } from "@supabase/supabase-js";
import { describe, expect, it } from "vitest";

const enabled = process.env.RUN_LOCAL_INTEGRATION === "1";
const suite = enabled ? describe : describe.skip;

suite("Supabase local auth และ organization bootstrap", () => {
  it("login, profile trigger, bootstrap transaction และ RLS ทำงานร่วมกัน", async () => {
    const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
    expect(url).toBeTruthy();
    expect(key).toBeTruthy();
    const client = createClient(url as string, key as string);
    const { data: auth, error: loginError } = await client.auth.signInWithPassword({ email: "owner@dormitory.local", password: "DormitoryLocal!2569" });
    expect(loginError).toBeNull();
    expect(auth.user).toBeTruthy();

    const { data: profile, error: profileError } = await client.from("profiles").select("id,display_name").eq("id", auth.user?.id as string).single();
    expect(profileError).toBeNull();
    expect(profile?.display_name).toBe("เจ้าของหอพัก Local");

    const { data: existing } = await client.from("organization_members").select("organization_id,role").maybeSingle();
    if (!existing) {
      const { error } = await client.rpc("bootstrap_organization", { organization_name: "บริษัท ทดสอบหอพัก จำกัด", dormitory_name: "หอพัก Local Development", dormitory_code: "LOCAL-01", dormitory_address: "1 ถนนทดสอบ กรุงเทพมหานคร" });
      expect(error).toBeNull();
    }
    const { data: membership, error: membershipError } = await client.from("organization_members").select("organization_id,role").single();
    expect(membershipError).toBeNull();
    expect(membership?.role).toBe("owner");
    const { data: dormitories, error: dormitoryError } = await client.from("dormitories").select("code,name");
    expect(dormitoryError).toBeNull();
    expect(dormitories?.some((item) => item.code === "LOCAL-01")).toBe(true);
  });
});
