import "server-only";
import { createCipheriv, createDecipheriv, createHash, randomBytes } from "node:crypto";

function encryptionKey() {
  const secret = process.env.ENCRYPTION_KEY;
  if (!secret || secret.length < 32) throw new Error("ENCRYPTION_KEY_NOT_CONFIGURED");
  return createHash("sha256").update(secret, "utf8").digest();
}

export function encryptPii(value: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", encryptionKey(), iv);
  const ciphertext = Buffer.concat([cipher.update(value, "utf8"), cipher.final()]);
  return ["v1", iv.toString("base64url"), cipher.getAuthTag().toString("base64url"), ciphertext.toString("base64url")].join(".");
}

export function decryptPii(payload: string): string {
  const [version, iv, tag, ciphertext] = payload.split(".");
  if (version !== "v1" || !iv || !tag || !ciphertext) throw new Error("INVALID_ENCRYPTED_VALUE");
  const decipher = createDecipheriv("aes-256-gcm", encryptionKey(), Buffer.from(iv, "base64url"));
  decipher.setAuthTag(Buffer.from(tag, "base64url"));
  return Buffer.concat([decipher.update(Buffer.from(ciphertext, "base64url")), decipher.final()]).toString("utf8");
}

export function maskIdentity(last4: string | null): string { return last4 ? `*********${last4}` : "—"; }
