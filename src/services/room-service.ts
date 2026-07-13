import type { SupabaseClient } from "@supabase/supabase-js";

interface Scope { organizationId: string; dormitoryId: string }
export class RoomService {
  constructor(private readonly db: SupabaseClient, private readonly scope: Scope) {}

  async createBuilding(input: { code: string; name: string; floorCount: number }) {
    const { data, error } = await this.db.rpc("create_building_with_floors", { target_dormitory_id: this.scope.dormitoryId, building_code: input.code, building_name: input.name, number_of_floors: input.floorCount });
    if (error) throw error;
    return data as string;
  }

  async createRoomType(input: { name: string; baseRent: string; deposit: string; maxOccupants: number }) {
    const { data, error } = await this.db.from("room_types").insert({ organization_id: this.scope.organizationId, dormitory_id: this.scope.dormitoryId, name: input.name, base_rent: input.baseRent, deposit: input.deposit, max_occupants: input.maxOccupants }).select("id").single();
    if (error) throw error;
    return data.id as string;
  }

  async createRoom(input: { floorId: string; roomTypeId: string; code: string; roomNumber: string; monthlyRent: string; waterMeterNumber?: string; electricMeterNumber?: string }) {
    const { data: floor, error: floorError } = await this.db.from("floors").select("id,building_id").eq("id", input.floorId).eq("dormitory_id", this.scope.dormitoryId).single();
    if (floorError || !floor) throw new Error("FLOOR_MISMATCH");
    const { data: type, error: typeError } = await this.db.from("room_types").select("id").eq("id", input.roomTypeId).eq("dormitory_id", this.scope.dormitoryId).single();
    if (typeError || !type) throw new Error("ROOM_TYPE_MISMATCH");
    const { data, error } = await this.db.from("rooms").insert({ organization_id: this.scope.organizationId, dormitory_id: this.scope.dormitoryId, building_id: floor.building_id, floor_id: input.floorId, room_type_id: input.roomTypeId, code: input.code.toUpperCase(), room_number: input.roomNumber, monthly_rent: input.monthlyRent, water_meter_number: input.waterMeterNumber || null, electric_meter_number: input.electricMeterNumber || null }).select("id").single();
    if (error) throw error;
    return data.id as string;
  }
}
