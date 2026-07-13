import { readFile } from "node:fs/promises";
import { expect, test } from "@playwright/test";

test("ลงลายเซ็นบน Canvas และดาวน์โหลด PDF พร้อมหลักฐาน", async ({ page }) => {
  await page.goto("/login"); await page.getByLabel("อีเมล").fill("owner@dormitory.local"); await page.getByLabel("รหัสผ่าน").fill("DormitoryLocal!2569");
  await page.getByRole("button", { name: "เข้าสู่ระบบ" }).click(); await expect(page).toHaveURL(/\/$/); await page.goto("/contracts");
  await page.getByRole("link", { name: "ตรวจรับ/ลงนาม" }).first().click(); await expect(page.getByRole("heading", { name: /CTR-/ })).toBeVisible();
  const tenantPending = page.getByText("รอลายเซ็นผู้เช่า", { exact: true });
  if (await tenantPending.count() > 0) {
    const canvas = page.locator("canvas"); await canvas.scrollIntoViewIfNeeded(); const box = await canvas.boundingBox(); expect(box).toBeTruthy();
    if (box) { await page.mouse.move(box.x + 40, box.y + 90); await page.mouse.down(); await page.mouse.move(box.x + 130, box.y + 40, { steps: 8 }); await page.mouse.move(box.x + 220, box.y + 100, { steps: 8 }); await page.mouse.up(); }
    await page.getByRole("checkbox").check(); await page.getByRole("button", { name: "ยืนยันและบันทึกลายเซ็น" }).click();
    await expect(page.getByText("บันทึกลายเซ็นและหลักฐานการลงนามสำเร็จ")).toBeVisible();
  }
  await expect(page.getByText("สัญญามีลายเซ็นแล้ว แบบตรวจรับถูกล็อกเพื่อรักษาหลักฐานเดิม")).toBeVisible();
  const [download] = await Promise.all([page.waitForEvent("download"), page.getByRole("link", { name: "ดาวน์โหลด PDF" }).click()]);
  const path = await download.path(); expect(path).toBeTruthy(); const bytes = await readFile(path as string);
  expect(bytes.subarray(0,4).toString()).toBe("%PDF"); expect(bytes.byteLength).toBeGreaterThan(5000);
});
