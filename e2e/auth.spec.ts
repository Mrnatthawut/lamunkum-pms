import { expect, test } from "@playwright/test";

test("Owner login ผ่านหน้าเว็บและเข้าสู่ Dashboard", async ({ page }) => {
  await page.goto("/login");
  await page.getByLabel("อีเมล").fill("owner@dormitory.local");
  await page.getByLabel("รหัสผ่าน").fill("DormitoryLocal!2569");
  await page.getByRole("button", { name: "เข้าสู่ระบบ" }).click();
  await expect(page).toHaveURL(/\/$/);
  await expect(page.getByRole("heading", { name: "ภาพรวมวันนี้" })).toBeVisible();
  await expect(page.getByText("อีเมลหรือรหัสผ่านไม่ถูกต้อง")).toHaveCount(0);
});
