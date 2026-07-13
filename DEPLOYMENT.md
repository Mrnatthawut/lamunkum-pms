# Production Deployment Checklist

1. สร้าง Supabase project และสำรองข้อมูลก่อน migration
2. รัน migration ตามลำดับและทดสอบ RLS ด้วยบัญชีแต่ละ role
3. ตั้ง environment variables ใน Vercel โดย secret ทั้งหมดเป็น server-only
4. ตั้ง Auth redirect URL, custom domain และ LINE webhook HTTPS
5. รัน `npm run lint && npm run typecheck && npm run test && npm run build`
6. ตรวจ CSP, rate limit, private storage, signed URL และ cron secret
7. ทำ smoke test flow invoice → payment approval → ledger → receipt และทดสอบ restore backup
