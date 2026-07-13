import { createClient } from "@supabase/supabase-js";
import { describe, expect, it } from "vitest";

const suite = process.env.RUN_LOCAL_INTEGRATION === "1" ? describe : describe.skip;
suite("Reservation และ Contract บน Supabase Local", () => {
  it("จองห้อง ยืนยัน ทำสัญญา และย้ายเข้าใน transaction", async () => {
    const client = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL as string, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY as string);
    const { error: loginError } = await client.auth.signInWithPassword({ email: "owner@dormitory.local", password: "DormitoryLocal!2569" });
    expect(loginError).toBeNull();
    const { data: dormitory } = await client.from("dormitories").select("id,organization_id").limit(1).single();
    const { data: tenant } = await client.from("tenants").select("id").eq("phone", "0800000001").single();
    expect(dormitory && tenant).toBeTruthy();

    let { data: building } = await client.from("buildings").select("id").eq("dormitory_id", dormitory?.id as string).eq("code", "CT").maybeSingle();
    if (!building) {
      const created = await client.rpc("create_building_with_floors", { target_dormitory_id: dormitory?.id, building_code: "CT", building_name: "อาคารทดสอบสัญญา", number_of_floors: 1 });
      expect(created.error).toBeNull(); building = { id: created.data as string };
    }
    const { data: floor } = await client.from("floors").select("id").eq("building_id", building.id).single();
    let { data: roomType } = await client.from("room_types").select("id").eq("dormitory_id", dormitory?.id as string).eq("name", "ห้องทดสอบสัญญา").maybeSingle();
    if (!roomType) {
      const created = await client.from("room_types").insert({ organization_id: dormitory?.organization_id, dormitory_id: dormitory?.id, name: "ห้องทดสอบสัญญา", base_rent: "5000.00", deposit: "5000.00", max_occupants: 2 }).select("id").single();
      expect(created.error).toBeNull(); roomType = created.data;
    }
    let { data: room } = await client.from("rooms").select("id,status").eq("dormitory_id", dormitory?.id as string).eq("code", "CT901").maybeSingle();
    if (!room) {
      const created = await client.from("rooms").insert({ organization_id: dormitory?.organization_id, dormitory_id: dormitory?.id, building_id: building.id, floor_id: floor?.id, room_type_id: roomType?.id, code: "CT901", room_number: "CT901", monthly_rent: "5000.00" }).select("id,status").single();
      expect(created.error).toBeNull(); room = created.data;
    }
    const { data: existingContract } = await client.from("contracts").select("id").eq("room_id", room?.id as string).in("status", ["active", "expiring"]).maybeSingle();
    if (existingContract) {
      const { data: existingMoveIn } = await client.from("move_ins").select("contract_id").eq("contract_id", existingContract.id).single();
      expect(existingMoveIn?.contract_id).toBe(existingContract.id); return;
    }

    const today = new Date().toISOString().slice(0, 10);
    const endDate = `${Number(today.slice(0, 4)) + 1}${today.slice(4)}`;
    const reservationResult = await client.rpc("create_reservation", { target_dormitory_id: dormitory?.id, target_room_id: room?.id, target_tenant_id: tenant?.id, target_expected_move_in_date: today, target_booking_amount: "1000.00", target_payment_method: "bank_transfer", target_expires_at: new Date(Date.now() + 86400000).toISOString(), target_status: "pending_payment", target_notes: "integration test" });
    expect(reservationResult.error).toBeNull();
    const reservationId = reservationResult.data as string;
    const confirmed = await client.rpc("set_reservation_status", { target_reservation_id: reservationId, target_status: "confirmed", target_reason: "" });
    expect(confirmed.error).toBeNull();
    const contractResult = await client.rpc("create_active_contract_and_move_in", { target_dormitory_id: dormitory?.id, target_room_id: room?.id, target_tenant_id: tenant?.id, target_reservation_id: reservationId, target_contract_date: today, target_start_date: today, target_end_date: endDate, target_monthly_rent: "5000.00", target_deposit: "5000.00", target_advance_rent: "0.00", target_due_day: 5, target_notice_days: 30, target_initial_water: "10.000", target_initial_electric: "20.000", target_inspection_notes: "สภาพปกติ", target_notes: "" });
    expect(contractResult.error).toBeNull();
    const { data: updatedRoom } = await client.from("rooms").select("status").eq("id", room?.id as string).single();
    const { data: reservation } = await client.from("reservations").select("status").eq("id", reservationId).single();
    const { data: moveIn } = await client.from("move_ins").select("initial_water_reading,initial_electric_reading").eq("contract_id", contractResult.data as string).single();
    expect(updatedRoom?.status).toBe("occupied");
    expect(reservation?.status).toBe("converted");
    expect(moveIn).toMatchObject({ initial_water_reading: 10, initial_electric_reading: 20 });
  });
});
