begin;
create extension if not exists pgcrypto;

create type public.app_role as enum ('super_admin','owner','manager','staff','accountant','maintenance','tenant');
create type public.room_status as enum ('vacant','occupied','reserved','cleaning','maintenance','suspended','moving_out','overdue','contract_expiring');
create type public.invoice_status as enum ('draft','pending_approval','issued','sent','viewed','partially_paid','pending_verification','paid','overdue','cancelled','written_off');
create type public.payment_status as enum ('pending','confirmed','rejected','cancelled','partially_refunded','refunded');

create table public.organizations (
 id uuid primary key default gen_random_uuid(), name text not null, tax_id text, address text, phone text, email text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, version integer not null default 1
);
create table public.profiles (
 id uuid primary key references auth.users(id) on delete restrict, display_name text not null, phone text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.organization_members (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
 profile_id uuid not null references public.profiles(id) on delete restrict, role public.app_role not null, active boolean not null default true,
 created_at timestamptz not null default now(), unique(organization_id, profile_id)
);
create table public.permissions (id uuid primary key default gen_random_uuid(), code text not null unique, description text not null);
create table public.role_permissions (role public.app_role not null, permission_id uuid not null references public.permissions(id), primary key(role, permission_id));
create table public.dormitories (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
 code text not null, name text not null, address text not null, phone text, timezone text not null default 'Asia/Bangkok', currency char(3) not null default 'THB', due_day smallint not null default 5 check(due_day between 1 and 28),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, version integer not null default 1,
 unique(organization_id, code)
);
create table public.buildings (id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id), dormitory_id uuid not null references public.dormitories(id), code text not null, name text not null, floor_count integer not null check(floor_count > 0), created_at timestamptz not null default now(), unique(dormitory_id, code));
create table public.floors (id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id), dormitory_id uuid not null references public.dormitories(id), building_id uuid not null references public.buildings(id), floor_number integer not null, name text, display_order integer not null default 0, created_at timestamptz not null default now(), unique(building_id, floor_number));
create table public.room_types (id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id), dormitory_id uuid not null references public.dormitories(id), name text not null, base_rent numeric(14,2) not null check(base_rent >= 0), deposit numeric(14,2) not null default 0 check(deposit >= 0), max_occupants integer not null default 2 check(max_occupants > 0), created_at timestamptz not null default now());
create table public.rooms (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id), dormitory_id uuid not null references public.dormitories(id), building_id uuid not null references public.buildings(id), floor_id uuid not null references public.floors(id), room_type_id uuid references public.room_types(id),
 code text not null, room_number text not null, monthly_rent numeric(14,2) not null check(monthly_rent >= 0), status public.room_status not null default 'vacant', water_meter_number text, electric_meter_number text, active boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, version integer not null default 1, unique(dormitory_id, code), unique(dormitory_id, room_number)
);
create index rooms_monitor_idx on public.rooms(dormitory_id, building_id, floor_id, status) where deleted_at is null;
create table public.tenants (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id), dormitory_id uuid not null references public.dormitories(id), profile_id uuid references public.profiles(id), tenant_code text not null, title text, first_name text not null, last_name text not null, phone text not null, email text, national_id_encrypted text, national_id_last4 char(4), line_user_id text unique, status text not null default 'active',
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, version integer not null default 1, unique(organization_id, tenant_code)
);
create index tenants_search_idx on public.tenants(organization_id, first_name, last_name, phone) where deleted_at is null;
create table public.contracts (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id), dormitory_id uuid not null references public.dormitories(id), tenant_id uuid not null references public.tenants(id), room_id uuid not null references public.rooms(id), contract_number text not null, start_date date not null, end_date date not null check(end_date > start_date), monthly_rent numeric(14,2) not null check(monthly_rent >= 0), deposit numeric(14,2) not null default 0 check(deposit >= 0), status text not null check(status in ('draft','awaiting_signature','active','expiring','expired','cancelled','renewed')), created_at timestamptz not null default now(), updated_at timestamptz not null default now(), version integer not null default 1, unique(organization_id, contract_number)
);
create unique index one_active_contract_per_room on public.contracts(room_id) where status in ('active','expiring');
create table public.meters (id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id), dormitory_id uuid not null references public.dormitories(id), room_id uuid not null references public.rooms(id), meter_number text not null, meter_type text not null check(meter_type in ('water','electricity','other')), initial_reading numeric(16,3) not null default 0, active boolean not null default true, created_at timestamptz not null default now(), unique(dormitory_id, meter_number));
create table public.meter_readings (id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id), dormitory_id uuid not null references public.dormitories(id), meter_id uuid not null references public.meters(id), billing_month date not null, previous_reading numeric(16,3) not null, current_reading numeric(16,3) not null, units numeric(16,3) generated always as (current_reading - previous_reading) stored, meter_replaced boolean not null default false, edit_reason text, created_by uuid references public.profiles(id), created_at timestamptz not null default now(), check(current_reading >= previous_reading or meter_replaced), unique(meter_id, billing_month));
create table public.billing_cycles (id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id), dormitory_id uuid not null references public.dormitories(id), billing_month date not null, period_start date not null, period_end date not null, issue_date date not null, due_date date not null, status text not null default 'draft' check(status in ('draft','review','open','locked')), created_at timestamptz not null default now(), unique(dormitory_id,billing_month));
create table public.invoices (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id), dormitory_id uuid not null references public.dormitories(id), billing_cycle_id uuid not null references public.billing_cycles(id), room_id uuid not null references public.rooms(id), tenant_id uuid not null references public.tenants(id), invoice_number text not null, revision integer not null default 1, issue_date date not null, due_date date not null, currency char(3) not null default 'THB', subtotal numeric(14,2) not null default 0, discount_total numeric(14,2) not null default 0, tax_total numeric(14,2) not null default 0, total numeric(14,2) not null check(total >= 0), balance numeric(14,2) not null check(balance >= 0), status public.invoice_status not null default 'draft', created_at timestamptz not null default now(), updated_at timestamptz not null default now(), version integer not null default 1, unique(organization_id, invoice_number), unique(billing_cycle_id, room_id, revision)
);
create index invoices_tenant_idx on public.invoices(tenant_id, issue_date desc);
create table public.invoice_items (id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id), invoice_id uuid not null references public.invoices(id) on delete restrict, code text not null, description text not null, quantity numeric(14,3) not null, unit text not null, unit_price numeric(14,2) not null, discount numeric(14,2) not null default 0, tax_rate numeric(6,3) not null default 0, line_total numeric(14,2) not null, created_at timestamptz not null default now());
create table public.payments (id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id), dormitory_id uuid not null references public.dormitories(id), tenant_id uuid not null references public.tenants(id), payment_number text not null, idempotency_key text not null, paid_at timestamptz not null, amount numeric(14,2) not null check(amount > 0), currency char(3) not null default 'THB', method text not null, status public.payment_status not null default 'pending', verified_by uuid references public.profiles(id), verified_at timestamptz, rejection_reason text, created_at timestamptz not null default now(), unique(organization_id,payment_number), unique(organization_id,idempotency_key));
create table public.payment_allocations (id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id), payment_id uuid not null references public.payments(id) on delete restrict, invoice_id uuid not null references public.invoices(id) on delete restrict, amount numeric(14,2) not null check(amount > 0), created_at timestamptz not null default now(), unique(payment_id,invoice_id));
create table public.financial_ledger (id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id), dormitory_id uuid not null references public.dormitories(id), transaction_type text not null check(transaction_type in ('invoice','payment','refund','credit','deposit','adjustment')), entity_id uuid not null, debit numeric(14,2) not null default 0, credit numeric(14,2) not null default 0, currency char(3) not null default 'THB', occurred_at timestamptz not null default now(), created_at timestamptz not null default now(), check(debit >= 0 and credit >= 0 and (debit = 0 or credit = 0)));
create table public.receipts (id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id), dormitory_id uuid not null references public.dormitories(id), payment_id uuid not null unique references public.payments(id) on delete restrict, receipt_number text not null, verification_token_hash text not null unique, amount numeric(14,2) not null, currency char(3) not null default 'THB', issued_at timestamptz not null default now(), voided_at timestamptz, void_reason text, unique(organization_id,receipt_number));
create table public.document_sequences (id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id), dormitory_id uuid references public.dormitories(id), document_type text not null, period text not null, current_value bigint not null default 0, prefix text not null, updated_at timestamptz not null default now(), unique(organization_id,dormitory_id,document_type,period));
create table public.line_webhook_events (id uuid primary key default gen_random_uuid(), organization_id uuid references public.organizations(id), webhook_event_id text not null unique, event_type text not null, received_at timestamptz not null default now(), processed_at timestamptz, error_code text);
create table public.line_message_logs (id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id), dormitory_id uuid references public.dormitories(id), tenant_id uuid references public.tenants(id), line_user_id text not null, message_type text not null, entity_type text, entity_id uuid, idempotency_key text not null, status text not null default 'queued', retry_count integer not null default 0, response jsonb, error text, created_at timestamptz not null default now(), sent_at timestamptz, unique(organization_id,idempotency_key));
create table public.audit_logs (id uuid primary key default gen_random_uuid(), organization_id uuid references public.organizations(id), dormitory_id uuid references public.dormitories(id), actor_id uuid references public.profiles(id), action text not null, entity_type text not null, entity_id uuid, before_data jsonb, after_data jsonb, ip inet, user_agent text, created_at timestamptz not null default now());
create index audit_logs_lookup_idx on public.audit_logs(organization_id, created_at desc);

create or replace function public.current_profile_id() returns uuid language sql stable security definer set search_path = '' as $$ select auth.uid() $$;
create or replace function public.is_member_of(org_id uuid) returns boolean language sql stable security definer set search_path = '' as $$ select exists(select 1 from public.organization_members m where m.organization_id=org_id and m.profile_id=auth.uid() and m.active) $$;
create or replace function public.is_tenant_of(target uuid) returns boolean language sql stable security definer set search_path = '' as $$ select exists(select 1 from public.tenants t where t.id=target and t.profile_id=auth.uid() and t.deleted_at is null) $$;
create or replace function public.has_permission(permission_code text) returns boolean language sql stable security definer set search_path = '' as $$ select exists(select 1 from public.organization_members m join public.role_permissions rp on rp.role=m.role join public.permissions p on p.id=rp.permission_id where m.profile_id=auth.uid() and m.active and p.code=permission_code) $$;

alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.dormitories enable row level security;
alter table public.buildings enable row level security;
alter table public.floors enable row level security;
alter table public.room_types enable row level security;
alter table public.rooms enable row level security;
alter table public.tenants enable row level security;
alter table public.contracts enable row level security;
alter table public.meters enable row level security;
alter table public.meter_readings enable row level security;
alter table public.billing_cycles enable row level security;
alter table public.invoices enable row level security;
alter table public.invoice_items enable row level security;
alter table public.payments enable row level security;
alter table public.payment_allocations enable row level security;
alter table public.financial_ledger enable row level security;
alter table public.receipts enable row level security;
alter table public.line_message_logs enable row level security;
alter table public.audit_logs enable row level security;

create policy organization_member_read on public.organizations for select using(public.is_member_of(id));
create policy member_scope on public.organization_members for select using(public.is_member_of(organization_id));
create policy dormitory_scope on public.dormitories for all using(public.is_member_of(organization_id)) with check(public.is_member_of(organization_id));
create policy building_scope on public.buildings for all using(public.is_member_of(organization_id)) with check(public.is_member_of(organization_id));
create policy floor_scope on public.floors for all using(public.is_member_of(organization_id)) with check(public.is_member_of(organization_id));
create policy room_type_scope on public.room_types for all using(public.is_member_of(organization_id)) with check(public.is_member_of(organization_id));
create policy room_scope on public.rooms for all using(public.is_member_of(organization_id)) with check(public.is_member_of(organization_id));
create policy tenant_staff_scope on public.tenants for all using(public.is_member_of(organization_id)) with check(public.is_member_of(organization_id));
create policy tenant_self_read on public.tenants for select using(public.is_tenant_of(id));
create policy contract_staff_scope on public.contracts for all using(public.is_member_of(organization_id)) with check(public.is_member_of(organization_id));
create policy contract_tenant_read on public.contracts for select using(public.is_tenant_of(tenant_id));
create policy invoice_staff_scope on public.invoices for all using(public.is_member_of(organization_id)) with check(public.is_member_of(organization_id));
create policy invoice_tenant_read on public.invoices for select using(public.is_tenant_of(tenant_id));
create policy payment_staff_scope on public.payments for all using(public.is_member_of(organization_id)) with check(public.is_member_of(organization_id));
create policy payment_tenant_read on public.payments for select using(public.is_tenant_of(tenant_id));
create policy receipt_staff_scope on public.receipts for all using(public.is_member_of(organization_id)) with check(public.is_member_of(organization_id));

insert into public.permissions(code,description) values
('rooms.read','ดูห้องพัก'),('rooms.create','เพิ่มห้องพัก'),('rooms.update','แก้ไขห้องพัก'),('rooms.delete','ยกเลิกห้องพัก'),('tenants.read','ดูผู้เช่า'),('contracts.manage','จัดการสัญญา'),('invoices.manage','จัดการใบแจ้งหนี้'),('payments.approve','อนุมัติการชำระ'),('receipts.issue','ออกใบเสร็จ'),('reports.finance','ดูรายงานการเงิน'),('settings.manage','จัดการตั้งค่า'),('users.manage','จัดการผู้ใช้') on conflict do nothing;
commit;
