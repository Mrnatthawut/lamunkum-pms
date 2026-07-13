import { expect, test } from "@playwright/test";

test("Owner สร้างงานซ่อม อัปเดต SLA และเปิดบทสนทนา", async ({ page }) => {
  await page.goto("/login");
  await page.getByLabel("อีเมล").fill("owner@dormitory.local");
  await page.getByLabel("รหัสผ่าน").fill("DormitoryLocal!2569");
  await page.getByRole("button", { name: "เข้าสู่ระบบ" }).click();

  await page.getByRole("link", { name: "แจ้งซ่อม" }).click();
  await expect(page.getByRole("heading", { name: "งานแจ้งซ่อม" })).toBeVisible();
  await page.getByText("สร้างงานแจ้งซ่อม", { exact: true }).click();
  await page.getByLabel("ห้อง").selectOption({ index: 1 });
  await page.getByLabel("หัวข้อ").fill("ตรวจสอบก๊อกน้ำ E2E");
  await page.getByLabel("รายละเอียด").fill("พบก๊อกน้ำรั่วบริเวณอ่างล้างหน้า");
  await page.getByRole("button", { name: "สร้างงานและเริ่ม SLA" }).click();
  await expect(page.getByText("สร้างงานแจ้งซ่อมและกำหนด SLA สำเร็จ")).toBeVisible();
  await page.reload();
  await expect(page.getByText("ตรวจสอบก๊อกน้ำ E2E").first()).toBeVisible();

  await page.getByRole("link", { name: "กล่องข้อความ" }).click();
  await expect(page.getByRole("heading", { name: "กล่องข้อความ", level: 1 })).toBeVisible();
  await page.getByText("เริ่มบทสนทนา", { exact: true }).click();
  await page.getByLabel("ผู้เช่า").selectOption({ index: 1 });
  await page.getByLabel("หัวข้อ").fill("ติดตามงานซ่อม E2E");
  await page.getByLabel("ข้อความ").fill("เจ้าหน้าที่ได้รับเรื่องและกำลังตรวจสอบ");
  await page.getByRole("button", { name: "สร้างและส่งข้อความ" }).click();
  await expect(page.getByText(/สร้างบทสนทนาแล้ว/)).toBeVisible();
  await page.reload();
  await expect(page.getByText("ติดตามงานซ่อม E2E").first()).toBeVisible();
});
