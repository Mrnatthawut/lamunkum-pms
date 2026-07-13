import { describe, expect, it } from "vitest";
import { validateImageFile } from "@/lib/security/uploads";

describe("Server image validation", () => {
  it("ยอมรับ PNG จาก magic bytes และสร้าง SHA-256", async () => {
    const bytes = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAF/gL+XfVQAAAAAElFTkSuQmCC", "base64");
    const result = await validateImageFile(new File([bytes], "signature.png", { type: "image/png" }), { maxBytes: 1024, allowWebp: false });
    expect(result.mimeType).toBe("image/png"); expect(result.sha256).toMatch(/^[a-f0-9]{64}$/);
  });

  it("ปฏิเสธไฟล์ปลอมที่อ้าง MIME เป็นรูป", async () => {
    await expect(validateImageFile(new File(["not an image"], "fake.png", { type: "image/png" }), { maxBytes: 1024, allowWebp: false })).rejects.toThrow("INVALID_FILE_TYPE");
  });

  it("ปฏิเสธไฟล์เกินขนาด", async () => {
    await expect(validateImageFile(new File([new Uint8Array(20)], "large.png", { type: "image/png" }), { maxBytes: 10, allowWebp: false })).rejects.toThrow("INVALID_FILE_SIZE");
  });
});
