import { expect, test } from "@playwright/test";

test.beforeEach(async ({ page }) => {
  await page.goto("/login");
  await page.getByLabel("อีเมล").fill("owner@dormitory.local");
  await page.getByLabel("รหัสผ่าน").fill("DormitoryLocal!2569");
  await page.getByRole("button", { name: "เข้าสู่ระบบ" }).click();
  await expect(page).toHaveURL(/\/$/);
});

test("สร้างอาคารและห้องผ่าน UI แล้วแสดงในรายการ", async ({ page }) => {
  const suffix = String(Date.now()).slice(-6);
  const buildingCode = `T${suffix}`;
  const roomCode = `${buildingCode}01`;
  await page.goto("/rooms");
  await expect(page.getByRole("heading", { name: "อาคาร ชั้น และห้องพัก" })).toBeVisible();
  await expect(page.getByText("A101")).toBeVisible();

  await page.getByLabel("รหัสอาคาร").fill(buildingCode);
  await page.getByLabel("ชื่ออาคาร").fill(`อาคารทดสอบ ${suffix}`);
  await page.getByLabel("จำนวนชั้น").fill("1");
  await page.getByRole("button", { name: "สร้างอาคารและชั้น" }).click();
  await expect(page.getByText("บันทึกสำเร็จ").first()).toBeVisible();

  await page.locator('select[name="floorId"]').selectOption({ label: `${buildingCode} · ชั้น 1` });
  await page.getByLabel("รหัสห้อง").fill(roomCode);
  await page.getByLabel("หมายเลขหน้าห้อง").fill(roomCode);
  await page.getByRole("button", { name: "เพิ่มห้องพัก" }).click();
  await expect(page.getByText(roomCode).first()).toBeVisible();
});
