import { readFile } from "node:fs/promises";
import { expect, test } from "@playwright/test";

test("Owner เปิด Template และดาวน์โหลด Contract PDF ภาษาไทย", async ({ page }) => {
  await page.goto("/login");
  await page.getByLabel("อีเมล").fill("owner@dormitory.local");
  await page.getByLabel("รหัสผ่าน").fill("DormitoryLocal!2569");
  await page.getByRole("button", { name: "เข้าสู่ระบบ" }).click();
  await expect(page).toHaveURL(/\/$/);
  await page.goto("/contracts/templates");
  await expect(page.getByRole("heading", { name: "Template สัญญาเช่า" })).toBeVisible();
  await expect(page.getByText("Version 1")).toBeVisible();
  await page.goto("/contracts");
  const generate = page.getByRole("button", { name: "สร้าง PDF Snapshot" }).first();
  if (await generate.count()) { await generate.click(); await expect(page.getByRole("link", { name: "ดาวน์โหลด PDF" }).first()).toBeVisible(); }
  const [download] = await Promise.all([page.waitForEvent("download"), page.getByRole("link", { name: "ดาวน์โหลด PDF" }).first().click()]);
  const path = await download.path();
  expect(path).toBeTruthy();
  const bytes = await readFile(path as string);
  expect(bytes.subarray(0, 4).toString()).toBe("%PDF");
  expect(download.suggestedFilename()).toMatch(/^CTR-\d{4}-\d{4}\.pdf$/);
});
