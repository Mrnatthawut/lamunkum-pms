begin;

alter table public.payments add column if not exists claimed_invoice_id uuid references public.invoices(id) on delete restrict;
alter table public.payments add column if not exists bank_name text;
alter table public.payments add column if not exists reference_number text;
alter table public.payments add column if not exists payer_note text;
alter table public.payments add column if not exists updated_at timestamptz not null default now();
alter table public.payments add column if not exists version integer not null default 1;
alter table public.receipts add column if not exists verification_token text unique;
alter table public.receipts add column if not exists received_by uuid references public.profiles(id) on delete restrict;

create table public.payment_proofs (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  dormitory_id uuid not null references public.dormitories(id) on delete restrict,
  payment_id uuid not null references public.payments(id) on delete restrict, storage_path text not null unique,
  mime_type text not null check(mime_type in ('image/png','image/jpeg','image/webp')), size_bytes bigint not null check(size_bytes between 1 and 5242880),
  file_sha256 text not null check(file_sha256 ~ '^[a-f0-9]{64}$'), created_at timestamptz not null default now(), unique(payment_id,storage_path)
);
create table public.credits (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  dormitory_id uuid not null references public.dormitories(id) on delete restrict, tenant_id uuid not null references public.tenants(id) on delete restrict,
  payment_id uuid not null references public.payments(id) on delete restrict, original_amount numeric(14,2) not null check(original_amount>0),
  balance numeric(14,2) not null check(balance>=0), currency char(3) not null default 'THB', status text not null default 'available' check(status in ('available','used','refunded','cancelled')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(payment_id)
);
create index payment_pending_idx on public.payments(dormitory_id,status,created_at desc);
create index payment_proofs_payment_idx on public.payment_proofs(payment_id);
create unique index one_payment_ledger_entry on public.financial_ledger(entity_id) where transaction_type='payment';

alter table public.payment_proofs enable row level security;
alter table public.credits enable row level security;
drop policy if exists payment_staff_scope on public.payments;
create policy payment_staff_scope on public.payments for all using(public.has_org_permission(organization_id,'payments.approve') or public.has_org_permission(organization_id,'invoices.manage')) with check(public.has_org_permission(organization_id,'payments.approve') or public.has_org_permission(organization_id,'invoices.manage'));
drop policy if exists payment_allocation_staff_scope on public.payment_allocations;
create policy payment_allocation_staff_scope on public.payment_allocations for select using(public.has_org_permission(organization_id,'payments.approve') or public.has_org_permission(organization_id,'invoices.manage'));
create policy payment_allocation_tenant_read on public.payment_allocations for select using(exists(select 1 from public.invoices i where i.id=invoice_id and public.is_tenant_of(i.tenant_id)));
create policy payment_proof_staff_read on public.payment_proofs for select using(public.has_org_permission(organization_id,'payments.approve') or public.has_org_permission(organization_id,'invoices.manage'));
create policy credit_staff_read on public.credits for select using(public.has_org_permission(organization_id,'payments.approve') or public.has_org_permission(organization_id,'reports.finance'));
create policy credit_tenant_read on public.credits for select using(public.is_tenant_of(tenant_id));
drop policy if exists receipt_staff_scope on public.receipts;
create policy receipt_staff_scope on public.receipts for select using(public.has_org_permission(organization_id,'receipts.issue') or public.has_org_permission(organization_id,'invoices.manage'));
create policy receipt_tenant_read on public.receipts for select using(exists(select 1 from public.payments p where p.id=payment_id and public.is_tenant_of(p.tenant_id)));

grant select,insert on public.payment_proofs to authenticated;
grant select on public.credits to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
('payment-proofs','payment-proofs',false,5242880,array['image/png','image/jpeg','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
create or replace function public.can_manage_payment_storage(object_name text) returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.organization_members m join public.role_permissions rp on rp.role=m.role join public.permissions p on p.id=rp.permission_id
    where m.profile_id=auth.uid() and m.active and m.organization_id::text=split_part(object_name,'/',1) and p.code in ('payments.approve','invoices.manage'))
$$;
revoke all on function public.can_manage_payment_storage(text) from public,anon;
grant execute on function public.can_manage_payment_storage(text) to authenticated;
create policy payment_proof_object_insert on storage.objects for insert to authenticated with check(bucket_id='payment-proofs' and public.can_manage_payment_storage(name));
create policy payment_proof_object_read on storage.objects for select to authenticated using(bucket_id='payment-proofs' and public.can_manage_payment_storage(name));

create or replace function public.submit_payment(
  target_invoice_id uuid,target_paid_at timestamptz,target_amount numeric,target_method text,target_bank_name text,target_reference_number text,target_payer_note text,
  target_idempotency_key text,target_proof_path text,target_proof_mime text,target_proof_size bigint,target_proof_sha256 text
) returns uuid language plpgsql security definer set search_path='' as $$
declare inv public.invoices%rowtype; sequence_value bigint; payment_no text; new_id uuid; period_key text; required_prefix text;
begin
  select * into inv from public.invoices where id=target_invoice_id for update;
  if inv.id is null then raise exception 'INVOICE_NOT_FOUND'; end if;
  if not (public.has_org_permission(inv.organization_id,'invoices.manage') or public.is_tenant_of(inv.tenant_id)) then raise exception 'FORBIDDEN'; end if;
  if inv.status not in ('issued','sent','viewed','partially_paid','overdue','pending_verification') or inv.balance<=0 then raise exception 'INVOICE_NOT_PAYABLE'; end if;
  if target_amount<=0 or target_amount>999999999999.99 or target_method not in ('cash','bank_transfer','promptpay','qr_payment','card','cheque','other')
    or length(target_idempotency_key)<16 then raise exception 'INVALID_PAYMENT'; end if;
  if target_method in ('bank_transfer','promptpay','qr_payment') and target_proof_path is null then raise exception 'PAYMENT_PROOF_REQUIRED'; end if;
  if target_proof_path is not null then
    required_prefix:=inv.organization_id::text||'/'||inv.dormitory_id::text||'/payments/';
    if left(target_proof_path,length(required_prefix))<>required_prefix or target_proof_path like '%..%' or target_proof_mime not in ('image/png','image/jpeg','image/webp')
      or target_proof_size not between 1 and 5242880 or target_proof_sha256 !~ '^[a-f0-9]{64}$' then raise exception 'INVALID_PAYMENT_PROOF'; end if;
  end if;
  select id into new_id from public.payments where organization_id=inv.organization_id and idempotency_key=target_idempotency_key;
  if new_id is not null then return new_id; end if;
  period_key:=to_char(timezone('Asia/Bangkok',target_paid_at),'YYYYMM');
  insert into public.document_sequences(organization_id,dormitory_id,document_type,period,current_value,prefix)
  values(inv.organization_id,inv.dormitory_id,'payment',period_key,1,'PAY') on conflict(organization_id,dormitory_id,document_type,period)
  do update set current_value=public.document_sequences.current_value+1,updated_at=now() returning current_value into sequence_value;
  payment_no:='PAY-'||period_key||'-'||lpad(sequence_value::text,4,'0');
  insert into public.payments(organization_id,dormitory_id,tenant_id,claimed_invoice_id,payment_number,idempotency_key,paid_at,amount,currency,method,bank_name,reference_number,payer_note)
  values(inv.organization_id,inv.dormitory_id,inv.tenant_id,inv.id,payment_no,target_idempotency_key,target_paid_at,target_amount,inv.currency,target_method,nullif(trim(target_bank_name),''),nullif(trim(target_reference_number),''),nullif(trim(target_payer_note),'')) returning id into new_id;
  if target_proof_path is not null then insert into public.payment_proofs(organization_id,dormitory_id,payment_id,storage_path,mime_type,size_bytes,file_sha256)
    values(inv.organization_id,inv.dormitory_id,new_id,target_proof_path,target_proof_mime,target_proof_size,target_proof_sha256); end if;
  update public.invoices set status='pending_verification',updated_at=now(),version=version+1 where id=inv.id and status<>'pending_verification';
  insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data)
  values(inv.organization_id,inv.dormitory_id,auth.uid(),'payment.submit','payment',new_id,jsonb_build_object('payment_number',payment_no,'invoice_id',inv.id,'amount',target_amount,'method',target_method));
  return new_id;
end $$;

create or replace function public.approve_payment(target_payment_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare pay public.payments%rowtype; inv public.invoices%rowtype; allocation_value numeric(14,2); excess_value numeric(14,2); sequence_value bigint;
  receipt_no text; receipt_id uuid; raw_token text; period_key text;
begin
  select * into pay from public.payments where id=target_payment_id for update;
  if pay.id is null then raise exception 'PAYMENT_NOT_FOUND'; end if;
  if not public.has_org_permission(pay.organization_id,'payments.approve') or not public.has_org_permission(pay.organization_id,'receipts.issue') then raise exception 'FORBIDDEN'; end if;
  if pay.status='confirmed' then select id,receipt_number,verification_token into receipt_id,receipt_no,raw_token from public.receipts where payment_id=pay.id;return jsonb_build_object('payment_number',pay.payment_number,'receipt_id',receipt_id,'receipt_number',receipt_no,'verification_token',raw_token);end if;
  if pay.status<>'pending' then raise exception 'PAYMENT_CANNOT_APPROVE'; end if;
  select * into inv from public.invoices where id=pay.claimed_invoice_id for update;
  if inv.id is null or inv.organization_id<>pay.organization_id or inv.tenant_id<>pay.tenant_id or inv.balance<=0 then raise exception 'INVOICE_NOT_PAYABLE'; end if;
  allocation_value:=least(pay.amount,inv.balance);excess_value:=pay.amount-allocation_value;
  insert into public.payment_allocations(organization_id,payment_id,invoice_id,amount) values(pay.organization_id,pay.id,inv.id,allocation_value);
  update public.invoices set balance=balance-allocation_value,status=case when balance-allocation_value=0 then 'paid'::public.invoice_status else 'partially_paid'::public.invoice_status end,updated_at=now(),version=version+1 where id=inv.id;
  update public.payments set status='confirmed',verified_by=auth.uid(),verified_at=now(),updated_at=now(),version=version+1 where id=pay.id;
  insert into public.financial_ledger(organization_id,dormitory_id,transaction_type,entity_id,debit,credit,currency,occurred_at)
  values(pay.organization_id,pay.dormitory_id,'payment',pay.id,0,pay.amount,pay.currency,pay.paid_at) on conflict do nothing;
  if excess_value>0 then insert into public.credits(organization_id,dormitory_id,tenant_id,payment_id,original_amount,balance,currency)
    values(pay.organization_id,pay.dormitory_id,pay.tenant_id,pay.id,excess_value,excess_value,pay.currency); end if;
  period_key:=to_char(timezone('Asia/Bangkok',now()),'YYYYMM');
  insert into public.document_sequences(organization_id,dormitory_id,document_type,period,current_value,prefix)
  values(pay.organization_id,pay.dormitory_id,'receipt',period_key,1,'REC') on conflict(organization_id,dormitory_id,document_type,period)
  do update set current_value=public.document_sequences.current_value+1,updated_at=now() returning current_value into sequence_value;
  receipt_no:='REC-'||period_key||'-'||lpad(sequence_value::text,4,'0');raw_token:=encode(extensions.gen_random_bytes(24),'hex');
  insert into public.receipts(organization_id,dormitory_id,payment_id,receipt_number,verification_token,verification_token_hash,amount,currency,received_by)
  values(pay.organization_id,pay.dormitory_id,pay.id,receipt_no,raw_token,encode(extensions.digest(raw_token,'sha256'),'hex'),pay.amount,pay.currency,auth.uid()) returning id into receipt_id;
  insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,before_data,after_data)
  values(pay.organization_id,pay.dormitory_id,auth.uid(),'payment.approve','payment',pay.id,jsonb_build_object('status','pending'),jsonb_build_object('status','confirmed','allocated',allocation_value,'credit',excess_value,'receipt_number',receipt_no));
  return jsonb_build_object('payment_number',pay.payment_number,'receipt_id',receipt_id,'receipt_number',receipt_no,'verification_token',raw_token);
end $$;

create or replace function public.reject_payment(target_payment_id uuid,target_reason text)
returns text language plpgsql security definer set search_path='' as $$
declare pay public.payments%rowtype; fallback_status public.invoice_status;
begin
  select * into pay from public.payments where id=target_payment_id for update;
  if pay.id is null then raise exception 'PAYMENT_NOT_FOUND'; end if;
  if not public.has_org_permission(pay.organization_id,'payments.approve') then raise exception 'FORBIDDEN'; end if;
  if pay.status<>'pending' or length(trim(target_reason))<3 then raise exception 'PAYMENT_CANNOT_REJECT'; end if;
  update public.payments set status='rejected',rejection_reason=trim(target_reason),verified_by=auth.uid(),verified_at=now(),updated_at=now(),version=version+1 where id=pay.id;
  select case when balance=total then 'issued'::public.invoice_status else 'partially_paid'::public.invoice_status end into fallback_status from public.invoices where id=pay.claimed_invoice_id;
  if not exists(select 1 from public.payments where claimed_invoice_id=pay.claimed_invoice_id and status='pending' and id<>pay.id) then update public.invoices set status=fallback_status,updated_at=now(),version=version+1 where id=pay.claimed_invoice_id;end if;
  insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,before_data,after_data)
  values(pay.organization_id,pay.dormitory_id,auth.uid(),'payment.reject','payment',pay.id,jsonb_build_object('status','pending'),jsonb_build_object('status','rejected','reason',trim(target_reason)));
  return pay.payment_number;
end $$;

create or replace function public.verify_receipt_public(target_token text)
returns table(receipt_number text,issued_at timestamptz,amount numeric,currency text,payment_number text,invoice_number text,dormitory_name text,room_number text,voided boolean)
language plpgsql stable security definer set search_path='' as $$
begin return query select r.receipt_number,r.issued_at,r.amount,r.currency::text,p.payment_number,i.invoice_number,d.name,rm.room_number,r.voided_at is not null
  from public.receipts r join public.payments p on p.id=r.payment_id join public.invoices i on i.id=p.claimed_invoice_id join public.dormitories d on d.id=r.dormitory_id join public.rooms rm on rm.id=i.room_id
  where r.verification_token_hash=encode(extensions.digest(target_token,'sha256'),'hex') and length(target_token)=48 limit 1;end
$$;

revoke all on function public.submit_payment(uuid,timestamptz,numeric,text,text,text,text,text,text,text,bigint,text),public.approve_payment(uuid),public.reject_payment(uuid,text) from public,anon;
grant execute on function public.submit_payment(uuid,timestamptz,numeric,text,text,text,text,text,text,text,bigint,text),public.approve_payment(uuid),public.reject_payment(uuid,text) to authenticated;
revoke all on function public.verify_receipt_public(text) from public;
grant execute on function public.verify_receipt_public(text) to anon,authenticated;

commit;
