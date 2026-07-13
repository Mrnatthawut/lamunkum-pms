import { expect, test } from "@playwright/test";

test("Owner สร้าง ยืนยัน และยกเลิกการจองผ่าน UI", async ({ page }) => {
  await page.goto("/login");
  await page.getByLabel("อีเมล").fill("owner@dormitory.local");
  await page.getByLabel("รหัสผ่าน").fill("DormitoryLocal!2569");
  await page.getByRole("button", { name: "เข้าสู่ระบบ" }).click();
  await expect(page).toHaveURL(/\/$/);
  await page.goto("/contracts");
  await expect(page.getByRole("heading", { name: "การจอง สัญญา และย้ายเข้า" })).toBeVisible();
  const reservationForm = page.locator("form").filter({ hasText: "บันทึกการจอง" });
  await reservationForm.locator('select[name="roomId"]').selectOption({ index: 1 });
  await reservationForm.locator('select[name="tenantId"]').selectOption({ index: 1 });
  await reservationForm.locator('input[name="bookingAmount"]').fill("500.00");
  await reservationForm.getByRole("button", { name: "บันทึกการจอง" }).click();
  await expect(page.getByText("สร้างการจองสำเร็จ")).toBeVisible();
  const list = page.locator("section").filter({ hasText: "รายการจองล่าสุด" });
  const latest = list.locator("article").first();
  await latest.getByRole("button", { name: "ยืนยันการจอง" }).click();
  await expect(latest.getByText("ยืนยันแล้ว")).toBeVisible();
  await latest.getByRole("button", { name: "ยกเลิกการจอง" }).click();
  await expect(latest.getByText("ยกเลิก", { exact: true })).toBeVisible();
});
