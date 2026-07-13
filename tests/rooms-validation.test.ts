import { describe, expect, it } from "vitest";
import { createBuildingSchema, createRoomSchema, createRoomTypeSchema } from "../src/features/rooms/schemas";

describe("Room management validation", () => {
  it("รับข้อมูลอาคารที่ถูกต้องและจำกัดจำนวนชั้น", () => { expect(createBuildingSchema.safeParse({ code: "A", name: "อาคาร A", floorCount: "3" }).success).toBe(true); expect(createBuildingSchema.safeParse({ code: "A", name: "อาคาร A", floorCount: "101" }).success).toBe(false); });
  it("ปฏิเสธจำนวนเงินเกินทศนิยมสองตำแหน่ง", () => expect(createRoomTypeSchema.safeParse({ name: "มาตรฐาน", baseRent: "4500.001", deposit: "4500", maxOccupants: "2" }).success).toBe(false));
  it("ปฏิเสธ UUID ปลอมจาก client", () => expect(createRoomSchema.safeParse({ buildingId: "x", floorId: "x", roomTypeId: "x", code: "A101", roomNumber: "101", monthlyRent: "4500" }).success).toBe(false));
});
