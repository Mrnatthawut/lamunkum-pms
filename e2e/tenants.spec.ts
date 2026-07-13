import {expect,test} from "@playwright/test";

test("เพิ่มและค้นหาผู้เช่าผ่าน UI โดย Mask เอกสาร",async({page})=>{
  await page.goto("/login");
  await page.getByLabel("อีเมล").fill("owner@dormitory.local");
  await page.getByLabel("รหัสผ่าน").fill("DormitoryLocal!2569");
  await page.getByRole("button",{name:"เข้าสู่ระบบ"}).click();
  await expect(page).toHaveURL(/\/$/);
  await page.goto("/tenants");
  const existing=page.getByText("สมหญิง อีทูอี");
  if(await existing.count()===0){
    await page.getByLabel("ชื่อ",{exact:true}).fill("สมหญิง");
    await page.getByLabel("นามสกุล").fill("อีทูอี");
    await page.locator('input[name="phone"]').fill("0800000010");
    await page.getByLabel("ประเภทเอกสาร").selectOption("passport");
    await page.getByLabel("เลขที่เอกสาร").fill("TEST12345");
    await page.getByRole("button",{name:"บันทึกผู้เช่า"}).click();
    await expect(page.getByText("เพิ่มผู้เช่าสำเร็จ")).toBeVisible();
  }
  await page.locator('input[name="q"]').fill("สมหญิง");
  await page.getByRole("button",{name:"ค้นหา"}).click();
  await expect(page.getByText("สมหญิง อีทูอี")).toBeVisible();
  await expect(page.getByText("*********2345")).toBeVisible();
});
