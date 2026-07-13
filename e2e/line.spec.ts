import { expect, test } from "@playwright/test";

test("Owner สร้างลิงก์ เชื่อม LINE Mock และส่ง Flex Message", async ({ page }) => {
  await page.goto("/login");
  await page.getByLabel("อีเมล").fill("owner@dormitory.local");
  await page.getByLabel("รหัสผ่าน").fill("DormitoryLocal!2569");
  await page.getByRole("button", { name: "เข้าสู่ระบบ" }).click();
  await page.getByRole("link", { name: "LINE / ข้อความ" }).click();

  await expect(page.getByRole("heading", { name: "LINE Integration" })).toBeVisible();
  await page.locator("#linkTenant").selectOption({ index: 1 });
  await page.getByRole("button", { name: "สร้าง" }).click();
  await expect(page.getByText("สร้างลิงก์เชื่อมต่อแล้ว ใช้ได้ 15 นาที")).toBeVisible();

  const link = await page.locator('input[readonly][value*="/line/link?code="]').inputValue();
  expect(link).toContain("/line/link?code=");
  await page.goto(link);
  await expect(page.getByRole("heading", { name: "เชื่อมบัญชีผู้เช่า" })).toBeVisible();
  await page.getByRole("button", { name: "เชื่อมบัญชีผู้เช่า" }).click();
  await expect(page.getByText("เชื่อมบัญชี LINE สำเร็จ")).toBeVisible();

  await page.goto("/line");
  const sendForm = page.locator("form").filter({ hasText: "ส่งข้อความทดสอบ" });
  await sendForm.locator('select[name="tenantId"]').selectOption({ index: 1 });
  await sendForm.locator('select[name="kind"]').selectOption("invoice");
  await sendForm.getByRole("button", { name: "ส่งข้อความ" }).click();
  await expect(page.getByText("ส่งข้อความสำเร็จผ่าน Mock Adapter")).toBeVisible();

  await page.reload();
  await expect(page.getByText("invoice_flex", { exact: true }).first()).toBeVisible();
});
