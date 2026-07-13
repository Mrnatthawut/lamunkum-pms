# Database

Migration แรกสร้างแกนองค์กร/หอพัก/ห้อง/ผู้เช่า/สัญญา/มิเตอร์/บิล/ชำระ/ledger/LINE/audit โดยห้าม cascade delete ข้อมูลการเงิน

```mermaid
erDiagram
 ORGANIZATIONS ||--o{ DORMITORIES : owns
 ORGANIZATIONS ||--o{ ORGANIZATION_MEMBERS : grants
 DORMITORIES ||--o{ BUILDINGS : contains
 BUILDINGS ||--o{ FLOORS : contains
 FLOORS ||--o{ ROOMS : contains
 ROOMS ||--o{ CONTRACTS : leased_by
 TENANTS ||--o{ CONTRACTS : signs
 ROOMS ||--o{ METERS : has
 METERS ||--o{ METER_READINGS : records
 BILLING_CYCLES ||--o{ INVOICES : generates
 INVOICES ||--o{ INVOICE_ITEMS : contains
 PAYMENTS ||--o{ PAYMENT_ALLOCATIONS : allocates
 INVOICES ||--o{ PAYMENT_ALLOCATIONS : receives
 PAYMENTS ||--o| RECEIPTS : proves
```

Invariant สำคัญ: active contract ต่อห้องเป็น partial unique index, invoice ต่อรอบ/ห้อง/revision ไม่ซ้ำ, document/payment idempotency ไม่ซ้ำ, เงินเป็น `numeric(14,2)`, readings เป็น `numeric(16,3)` และ audit/ledger เป็น append-only ใน UI
