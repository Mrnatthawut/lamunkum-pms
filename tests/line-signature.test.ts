import { describe, expect, it } from "vitest";
import { createLineSignature, verifyLineSignature } from "../src/lib/line/signature";
describe("LINE webhook", () => { it("ตรวจ raw body ด้วย HMAC SHA-256", () => { const body='{"events":[]}'; const signature=createLineSignature(body,"secret"); expect(verifyLineSignature(body,signature,"secret")).toBe(true); expect(verifyLineSignature(body+" ",signature,"secret")).toBe(false); }); });
