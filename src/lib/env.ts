import { z } from "zod";

const publicSchema = z.object({
  NEXT_PUBLIC_APP_NAME: z.string().default("Dormitory Management System"),
  NEXT_PUBLIC_APP_URL: z.url().default("http://localhost:3000"),
  NEXT_PUBLIC_SUPABASE_URL: z.url().optional(),
  NEXT_PUBLIC_SUPABASE_ANON_KEY: z.string().min(1).optional(),
});

export const publicEnv = publicSchema.parse({
  NEXT_PUBLIC_APP_NAME: process.env.NEXT_PUBLIC_APP_NAME,
  NEXT_PUBLIC_APP_URL: process.env.NEXT_PUBLIC_APP_URL,
  NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL || undefined,
  NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || undefined,
});

export function requireServerEnv(name: "LINE_CHANNEL_SECRET" | "LINE_CHANNEL_ACCESS_TOKEN" | "LINE_LOGIN_CHANNEL_ID" | "SUPABASE_SERVICE_ROLE_KEY") {
  const value = process.env[name];
  if (!value) throw new Error(`Missing server environment variable: ${name}`);
  return value;
}

export function lineMockMode(){return process.env.LINE_MOCK_MODE==="true"||(process.env.NODE_ENV!=="production"&&!process.env.LINE_CHANNEL_ACCESS_TOKEN);}
export function lineWebhookSecret(){if(process.env.LINE_CHANNEL_SECRET)return process.env.LINE_CHANNEL_SECRET;if(lineMockMode())return"local-line-mock-secret";throw new Error("Missing server environment variable: LINE_CHANNEL_SECRET");}
