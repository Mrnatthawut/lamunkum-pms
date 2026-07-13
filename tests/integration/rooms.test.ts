import { createClient } from "@supabase/supabase-js";
import { describe, expect, it } from "vitest";

const suite = process.env.RUN_LOCAL_INTEGRATION === "1" ? describe : describe.skip;
suite("Room management บน Supabase Local", () => {
  it("สร้างอาคารพร้อมชั้น ประเภทห้อง และห้องภายใต้ RLS", async () => {
    const client = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL as string, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY as string);
    const { error: loginError } = await client.auth.signInWithPassword({ email: "owner@dormitory.local", password: "DormitoryLocal!2569" });
    expect(loginError).toBeNull();
    const { data: dormitory } = await client.from("dormitories").select("id,organization_id").limit(1).single();
    expect(dormitory).toBeTruthy();

    let { data: building } = await client.from("buildings").select("id").eq("dormitory_id", dormitory?.id as string).eq("code", "A").maybeSingle();
    if (!building) {
      const { data: buildingId, error } = await client.rpc("create_building_with_floors", { target_dormitory_id: dormitory?.id as string, building_code: "A", building_name: "อาคาร A", number_of_floors: 3 });
      expect(error).toBeNull();
      building = { id: buildingId as string };
    }
    const { data: floors, error: floorsError } = await client.from("floors").select("id,floor_number").eq("building_id", building.id).order("floor_number");
    expect(floorsError).toBeNull();
    expect(floors).toHaveLength(3);

    let { data: roomType } = await client.from("room_types").select("id").eq("dormitory_id", dormitory?.id as string).eq("name", "ห้องมาตรฐาน").maybeSingle();
    if (!roomType) {
      const result = await client.from("room_types").insert({ organization_id: dormitory?.organization_id, dormitory_id: dormitory?.id, name: "ห้องมาตรฐาน", base_rent: "4500.00", deposit: "4500.00", max_occupants: 2 }).select("id").single();
      expect(result.error).toBeNull();
      roomType = result.data;
    }
    const { data: existingRoom } = await client.from("rooms").select("id").eq("dormitory_id", dormitory?.id as string).eq("code", "A101").maybeSingle();
    if (!existingRoom) {
      const { error } = await client.from("rooms").insert({ organization_id: dormitory?.organization_id, dormitory_id: dormitory?.id, building_id: building.id, floor_id: floors?.[0]?.id, room_type_id: roomType?.id, code: "A101", room_number: "101", monthly_rent: "4500.00", status: "vacant" });
      expect(error).toBeNull();
    }
    const { data: room, error: roomError } = await client.from("rooms").select("room_number,status,monthly_rent").eq("code", "A101").single();
    expect(roomError).toBeNull();
    expect(room?.room_number).toBe("101");
    expect(["vacant", "reserved", "occupied"]).toContain(room?.status);
  });
});
