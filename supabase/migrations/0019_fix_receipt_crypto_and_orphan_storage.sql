begin;

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

create or replace function public.verify_receipt_public(target_token text)
returns table(receipt_number text,issued_at timestamptz,amount numeric,currency text,payment_number text,invoice_number text,dormitory_name text,room_number text,voided boolean)
language plpgsql stable security definer set search_path='' as $$
begin return query select r.receipt_number,r.issued_at,r.amount,r.currency::text,p.payment_number,i.invoice_number,d.name,rm.room_number,r.voided_at is not null
  from public.receipts r join public.payments p on p.id=r.payment_id join public.invoices i on i.id=p.claimed_invoice_id join public.dormitories d on d.id=r.dormitory_id join public.rooms rm on rm.id=i.room_id
  where r.verification_token_hash=encode(extensions.digest(target_token,'sha256'),'hex') and length(target_token)=48 limit 1;end
$$;

create or replace function public.can_delete_orphan_payment_proof(object_name text) returns boolean language sql stable security definer set search_path='' as $$
  select public.can_manage_payment_storage(object_name) and not exists(select 1 from public.payment_proofs pp where pp.storage_path=object_name)
$$;
revoke all on function public.can_delete_orphan_payment_proof(text) from public,anon;
grant execute on function public.can_delete_orphan_payment_proof(text) to authenticated;
create policy payment_proof_orphan_delete on storage.objects for delete to authenticated using(bucket_id='payment-proofs' and public.can_delete_orphan_payment_proof(name));

revoke all on function public.approve_payment(uuid) from public,anon;
grant execute on function public.approve_payment(uuid) to authenticated;
revoke all on function public.verify_receipt_public(text) from public;
grant execute on function public.verify_receipt_public(text) to anon,authenticated;
commit;
