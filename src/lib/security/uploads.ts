import "server-only";
import { createHash } from "node:crypto";

export type ValidatedImage = { bytes: Uint8Array; mimeType: "image/png" | "image/jpeg" | "image/webp"; extension: "png" | "jpg" | "webp"; sha256: string; size: number };

function detectedType(bytes: Uint8Array) {
  if (bytes.length >= 8 && [137,80,78,71,13,10,26,10].every((value, index) => bytes[index] === value)) return { mimeType: "image/png" as const, extension: "png" as const };
  if (bytes.length >= 3 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255) return { mimeType: "image/jpeg" as const, extension: "jpg" as const };
  if (bytes.length >= 12 && new TextDecoder().decode(bytes.slice(0,4)) === "RIFF" && new TextDecoder().decode(bytes.slice(8,12)) === "WEBP") return { mimeType: "image/webp" as const, extension: "webp" as const };
  return null;
}

export async function validateImageFile(file: File, options: { maxBytes: number; allowWebp: boolean }): Promise<ValidatedImage> {
  if (!(file instanceof File) || file.size < 1 || file.size > options.maxBytes) throw new Error("INVALID_FILE_SIZE");
  const bytes = new Uint8Array(await file.arrayBuffer()); const detected = detectedType(bytes);
  if (!detected || (!options.allowWebp && detected.mimeType === "image/webp")) throw new Error("INVALID_FILE_TYPE");
  if (file.type && file.type !== detected.mimeType) throw new Error("MIME_MISMATCH");
  return { bytes, ...detected, size: bytes.byteLength, sha256: createHash("sha256").update(bytes).digest("hex") };
}
