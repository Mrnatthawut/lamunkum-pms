import { z } from "zod";

export const loginSchema = z.object({
  email: z.email("รูปแบบอีเมลไม่ถูกต้อง"),
  password: z.string().min(8, "รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร").max(128),
});

export interface AuthActionState {
  error?: string;
  fieldErrors?: Partial<Record<"email" | "password", string[]>>;
}
