import { describe, expect, it } from "vitest";
import { loginSchema } from "../src/features/auth/schemas";
import { bootstrapOrganizationSchema } from "../src/features/organizations/schemas";

describe("Auth และ onboarding validation", () => {
  it("ปฏิเสธอีเมลผิดรูปแบบและรหัสผ่านสั้น", () => expect(loginSchema.safeParse({ email: "bad", password: "123" }).success).toBe(false));
  it("ยอมรับข้อมูลกิจการที่ปลอดภัย", () => expect(bootstrapOrganizationSchema.safeParse({ organizationName: "บริษัท หอพัก จำกัด", dormitoryName: "บ้านสุขใจ", dormitoryCode: "BSJ-01", dormitoryAddress: "กรุงเทพมหานคร ประเทศไทย" }).success).toBe(true));
  it("ปฏิเสธรหัสหอพักที่มีอักขระพิเศษ", () => expect(bootstrapOrganizationSchema.safeParse({ organizationName: "บริษัท หอพัก จำกัด", dormitoryName: "บ้านสุขใจ", dormitoryCode: "<script>", dormitoryAddress: "กรุงเทพมหานคร ประเทศไทย" }).success).toBe(false));
});
