# Security Policy

ห้าม commit secret หรือข้อมูลส่วนบุคคลจริง ใช้ Vercel/Supabase secret manager, หมุน key เมื่อสงสัยว่ารั่ว และแจ้งช่องทางความปลอดภัยส่วนตัวของผู้ดูแลระบบแทน issue สาธารณะ

ก่อน production ต้องทดสอบ RLS ข้าม organization/tenant, เปิด MFA สำหรับ owner, rate limit auth/upload/webhook, ตรวจ magic bytes และขนาดไฟล์ฝั่ง server, ใช้ private bucket/signed URL, ตั้ง CSP ให้เหมาะกับ LIFF/PDF ที่ใช้งานจริง และตรวจ dependency advisory ทุก release Audit log ต้อง redact token/secret/เลขบัตรเต็ม และไม่อนุญาต update/delete ผ่าน role ปกติ
