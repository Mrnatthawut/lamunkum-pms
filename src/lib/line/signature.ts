import { createHmac, timingSafeEqual } from "node:crypto";

export function createLineSignature(rawBody: string, channelSecret: string) {
  return createHmac("sha256", channelSecret).update(rawBody, "utf8").digest("base64");
}

export function verifyLineSignature(rawBody: string, signature: string | null, channelSecret: string) {
  if (!signature) return false;
  const expected = Buffer.from(createLineSignature(rawBody, channelSecret));
  const received = Buffer.from(signature);
  return expected.length === received.length && timingSafeEqual(expected, received);
}
