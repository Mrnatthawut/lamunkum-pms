import type { NextConfig } from "next";

const isDevelopment = process.env.NODE_ENV === "development";
const scriptSources = ["'self'", "'unsafe-inline'", ...(isDevelopment ? ["'unsafe-eval'"] : [])].join(" ");
const connectSources = [
  "'self'",
  "https://*.supabase.co",
  "wss://*.supabase.co",
  "https://api.line.me",
  ...(isDevelopment ? ["http://127.0.0.1:54321", "ws://127.0.0.1:54321"] : []),
].join(" ");
const contentSecurityPolicy = [
  "default-src 'self'",
  "img-src 'self' data: blob: https://*.supabase.co",
  `script-src ${scriptSources}`,
  "style-src 'self' 'unsafe-inline'",
  `connect-src ${connectSources}`,
  "frame-ancestors 'none'",
  "base-uri 'self'",
  "form-action 'self'",
].join("; ");

const nextConfig: NextConfig = {
  poweredByHeader: false,
  reactStrictMode: true,
  allowedDevOrigins: ["127.0.0.1"],
  async headers() {
    return [{
      source: "/(.*)",
      headers: [
        { key: "X-Content-Type-Options", value: "nosniff" },
        { key: "X-Frame-Options", value: "DENY" },
        { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
        { key: "Permissions-Policy", value: "camera=(self), microphone=(), geolocation=(self)" },
        { key: "Content-Security-Policy", value: contentSecurityPolicy }
      ]
    }];
  }
};

export default nextConfig;
