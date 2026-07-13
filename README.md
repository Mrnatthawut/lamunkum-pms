# Dormitory Management System

ระบบบริหารหอพักแบบ multi-tenant ภาษาไทย พัฒนาโดย Next.js App Router, TypeScript strict, Tailwind CSS และ Supabase/PostgreSQL ข้อมูลเวลาเก็บเป็น UTC และแสดงผลเขตเวลา `Asia/Bangkok`; เงินใช้ `numeric`/decimal string และสกุล THB

## เริ่มต้นใช้งาน

ต้องมี Node.js 20.9 ขึ้นไป, npm และ Supabase CLI (กรณีใช้ฐานข้อมูล local)

```bash
cp .env.example .env.local
npm install
supabase start
supabase db reset
npm run dev
```

สำหรับ local Supabase ที่เริ่มด้วย CLI ให้ใช้คำสั่งนี้แทน เพื่อโหลด local key เข้าสู่ process โดยไม่บันทึก key ลง repository:

```bash
npx supabase start
bash scripts/create-local-owner.sh
npm run dev:local
```

บัญชี development คือ `owner@dormitory.local` / `DormitoryLocal!2569` ห้ามนำรหัสนี้ไปใช้บน Cloud หรือ production หลัง login ครั้งแรก ระบบจะแสดงฟอร์มสร้างกิจการและหอพักแรก ซึ่งเรียก PostgreSQL function แบบ transaction และสร้าง Owner membership ให้โดยอัตโนมัติ

หากยังไม่ตั้งค่า Supabase หน้าเว็บจะเปิดได้ในสถานะว่างโดยไม่ใช้ mock data เมื่อกำหนด `NEXT_PUBLIC_SUPABASE_URL` และ anon key แล้ว ข้อมูลจะถูกอ่านภายใต้ RLS ตาม session จริง

คำสั่งตรวจสอบ:

```bash
npm run lint
npm run typecheck
npm run test
npm run build
```

## Environment variables

- `NEXT_PUBLIC_APP_NAME`, `NEXT_PUBLIC_APP_URL`: ชื่อและ public URL
- `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`: ค่า public สำหรับ Supabase client (RLS ต้องเปิดเสมอ)
- `SUPABASE_SERVICE_ROLE_KEY`: server-only สำหรับงานระบบ ห้ามขึ้นต้น `NEXT_PUBLIC_`
- `DATABASE_URL`, `DIRECT_URL`: connection string สำหรับ migration/server tooling
- `LINE_CHANNEL_ID`, `LINE_CHANNEL_SECRET`, `LINE_CHANNEL_ACCESS_TOKEN`: Messaging API server-only
- `LINE_LOGIN_CHANNEL_ID`, `LINE_LOGIN_CHANNEL_SECRET`, `NEXT_PUBLIC_LINE_LIFF_ID`: LINE Login/LIFF; เปิดเผยได้เฉพาะ LIFF ID
- `CRON_SECRET`: ยืนยัน cron endpoint
- `DOCUMENT_SIGNING_SECRET`: ลงนาม verification token เอกสาร
- `ENCRYPTION_KEY`: เข้ารหัส PII ฝั่ง server; ใช้ secret อย่างน้อย 32 bytes จาก secret manager
- `APP_TIMEZONE`, `APP_CURRENCY`: ค่าเริ่มต้น `Asia/Bangkok`, `THB`

## Supabase และ LINE

สร้าง Supabase project แล้วรัน migration ใน `supabase/migrations` ตามลำดับ ตั้ง Site URL/Redirect URL เป็น `${NEXT_PUBLIC_APP_URL}/auth/callback` และห้ามปิด RLS ใน production เอกสารส่วนบุคคลต้องอยู่ private bucket และออก signed URL อายุสั้นเท่านั้น

สำหรับ LINE ให้สร้าง Official Account, เปิด Messaging API, ตั้ง webhook เป็น `https://โดเมน/api/line/webhook` แล้วออก channel access token จาก LINE Developers Console Endpoint ตรวจ `x-line-signature` กับ raw request body ก่อน parse อยู่แล้ว ใน local สามารถเว้น credential ได้ ยกเว้นเมื่อทดสอบ endpoint LINE

## Deployment

นำ repository เข้า Vercel, กำหนด environment variables แยก Preview/Production, deploy migration ไป Supabase ก่อน application และตั้ง custom domain/redirect URL/webhook ให้เป็น HTTPS สำรองฐานข้อมูลด้วย Supabase PITR หรือ scheduled logical backup และทดสอบ restore เป็นระยะ ดูรายละเอียดการตัดสินใจที่ [docs/architecture.md](docs/architecture.md), schema ที่ [docs/database.md](docs/database.md) และ security ที่ [SECURITY.md](SECURITY.md)

> เอกสารภาษี/PDPA/ลายเซ็นอิเล็กทรอนิกส์ในระบบเป็นเครื่องมือช่วยดำเนินงาน เจ้าของกิจการต้องให้นักบัญชีและผู้เชี่ยวชาญกฎหมายไทยตรวจสอบก่อนใช้จริง
