begin;

insert into public.permissions(code,description) values('move_outs.manage','จัดการการย้ายออก'),('deposits.manage','จัดการเงินประกัน') on conflict do nothing;
insert into public.role_permissions(role,permission_id) select role_name,p.id from unnest(array['super_admin','owner','manager']::public.app_role[]) role_name cross join public.permissions p where p.code in ('move_outs.manage','deposits.manage') on conflict do nothing;
insert into public.role_permissions(role,permission_id) select 'staff'::public.app_role,p.id from public.permissions p where p.code='move_outs.manage' on conflict do nothing;
insert into public.role_permissions(role,permission_id) select 'accountant'::public.app_role,p.id from public.permissions p where p.code='deposits.manage' on conflict do nothing;

create table public.move_outs (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  dormitory_id uuid not null references public.dormitories(id) on delete restrict, contract_id uuid not null references public.contracts(id) on delete restrict,
  tenant_id uuid not null references public.tenants(id) on delete restrict, room_id uuid not null references public.rooms(id) on delete restrict,
  move_out_number text not null, notice_date date not null, requested_move_out_date date not null, inspection_date date,
  actual_move_out_date date, final_water_reading numeric(16,3) check(final_water_reading>=0), final_electric_reading numeric(16,3) check(final_electric_reading>=0),
  damage_amount numeric(14,2) not null default 0 check(damage_amount>=0), cleaning_fee numeric(14,2) not null default 0 check(cleaning_fee>=0),
  utility_charge numeric(14,2) not null default 0 check(utility_charge>=0), other_deduction numeric(14,2) not null default 0 check(other_deduction>=0),
  deposit_balance_snapshot numeric(14,2), total_deduction numeric(14,2), refund_amount numeric(14,2), outstanding_invoice_balance numeric(14,2),
  inspection_notes text, internal_notes text, status text not null default 'notice_received' check(status in ('notice_received','inspection_scheduled','pending_settlement','completed','cancelled')),
  completed_by uuid references public.profiles(id) on delete restrict, completed_at timestamptz, created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), version integer not null default 1,
  unique(organization_id,move_out_number)
);
create unique index one_open_move_out_per_contract on public.move_outs(contract_id) where status in ('notice_received','inspection_scheduled','pending_settlement');
create index move_out_dormitory_status_idx on public.move_outs(dormitory_id,status,requested_move_out_date);

create table public.deposit_transactions (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  dormitory_id uuid not null references public.dormitories(id) on delete restrict, contract_id uuid not null references public.contracts(id) on delete restrict,
  tenant_id uuid not null references public.tenants(id) on delete restrict, move_out_id uuid references public.move_outs(id) on delete restrict,
  transaction_type text not null check(transaction_type in ('received','deduction','refund','adjustment')),
  direction text not null check(direction in ('in','out')), amount numeric(14,2) not null check(amount>0), currency char(3) not null default 'THB',
  transaction_date timestamptz not null, payment_method text, reference_number text, notes text, idempotency_key text not null,
  approved_by uuid references public.profiles(id) on delete restrict, created_at timestamptz not null default now(), unique(organization_id,idempotency_key)
);
create index deposit_contract_ledger_idx on public.deposit_transactions(contract_id,transaction_date,created_at);

alter table public.move_outs enable row level security;alter table public.deposit_transactions enable row level security;
create policy move_out_member_read on public.move_outs for select using(public.has_org_permission(organization_id,'move_outs.manage') or public.is_tenant_of(tenant_id));
create policy deposit_member_read on public.deposit_transactions for select using(public.has_org_permission(organization_id,'move_outs.manage') or public.has_org_permission(organization_id,'deposits.manage') or public.is_tenant_of(tenant_id));
grant select on public.move_outs,public.deposit_transactions to authenticated;

create or replace function public.record_deposit_receipt(target_contract_id uuid,target_amount numeric,target_transaction_date timestamptz,target_payment_method text,target_reference_number text,target_notes text,target_idempotency_key text)
returns uuid language plpgsql security definer set search_path='' as $$
declare c public.contracts%rowtype; received_total numeric; new_id uuid;
begin
  select * into c from public.contracts where id=target_contract_id for update;
  if c.id is null then raise exception 'CONTRACT_NOT_FOUND';end if;
  if not public.has_org_permission(c.organization_id,'deposits.manage') then raise exception 'FORBIDDEN';end if;
  select id into new_id from public.deposit_transactions where organization_id=c.organization_id and idempotency_key=target_idempotency_key;if new_id is not null then return new_id;end if;
  select coalesce(sum(case when direction='in' then amount else -amount end),0) into received_total from public.deposit_transactions where contract_id=c.id;
  if target_amount<=0 or received_total+target_amount>c.deposit or length(target_idempotency_key)<16 then raise exception 'INVALID_DEPOSIT_AMOUNT';end if;
  insert into public.deposit_transactions(organization_id,dormitory_id,contract_id,tenant_id,transaction_type,direction,amount,currency,transaction_date,payment_method,reference_number,notes,idempotency_key,approved_by)
  values(c.organization_id,c.dormitory_id,c.id,c.tenant_id,'received','in',target_amount,'THB',target_transaction_date,nullif(trim(target_payment_method),''),nullif(trim(target_reference_number),''),nullif(trim(target_notes),''),target_idempotency_key,auth.uid()) returning id into new_id;
  insert into public.financial_ledger(organization_id,dormitory_id,transaction_type,entity_id,debit,credit,currency,occurred_at) values(c.organization_id,c.dormitory_id,'deposit',new_id,0,target_amount,'THB',target_transaction_date);
  insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data) values(c.organization_id,c.dormitory_id,auth.uid(),'deposit.received','deposit_transaction',new_id,jsonb_build_object('contract_id',c.id,'amount',target_amount,'method',target_payment_method));
  return new_id;
end $$;

create or replace function public.request_move_out(target_contract_id uuid,target_notice_date date,target_requested_date date,target_inspection_date date,target_notes text)
returns uuid language plpgsql security definer set search_path='' as $$
declare c public.contracts%rowtype;sequence_value bigint;move_number text;new_id uuid;period_key text;
begin
  select * into c from public.contracts where id=target_contract_id for update;
  if c.id is null or c.status not in ('active','expiring') then raise exception 'CONTRACT_NOT_ACTIVE';end if;
  if not public.has_org_permission(c.organization_id,'move_outs.manage') then raise exception 'FORBIDDEN';end if;
  if target_requested_date<target_notice_date or target_inspection_date is not null and target_inspection_date<target_notice_date then raise exception 'INVALID_MOVE_OUT_DATES';end if;
  period_key:=to_char(timezone('Asia/Bangkok',now()),'YYYY');
  insert into public.document_sequences(organization_id,dormitory_id,document_type,period,current_value,prefix) values(c.organization_id,c.dormitory_id,'move_out',period_key,1,'MOUT')
  on conflict(organization_id,dormitory_id,document_type,period) do update set current_value=public.document_sequences.current_value+1,updated_at=now() returning current_value into sequence_value;
  move_number:='MOUT-'||period_key||'-'||lpad(sequence_value::text,4,'0');
  insert into public.move_outs(organization_id,dormitory_id,contract_id,tenant_id,room_id,move_out_number,notice_date,requested_move_out_date,inspection_date,inspection_notes,status,created_by)
  values(c.organization_id,c.dormitory_id,c.id,c.tenant_id,c.room_id,move_number,target_notice_date,target_requested_date,target_inspection_date,nullif(trim(target_notes),''),case when target_inspection_date is null then 'notice_received' else 'inspection_scheduled' end,auth.uid()) returning id into new_id;
  update public.rooms set status='moving_out',updated_at=now(),version=version+1 where id=c.room_id;
  insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data) values(c.organization_id,c.dormitory_id,auth.uid(),'move_out.request','move_out',new_id,jsonb_build_object('contract_id',c.id,'requested_date',target_requested_date,'notice_days',(target_requested_date-target_notice_date)));
  return new_id;
end $$;

create or replace function public.complete_move_out(target_move_out_id uuid,target_actual_date date,target_final_water numeric,target_final_electric numeric,target_damage numeric,target_cleaning numeric,target_utility numeric,target_other numeric,target_inspection_notes text,target_internal_notes text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare mo public.move_outs%rowtype;c public.contracts%rowtype;deposit_balance numeric;outstanding numeric;deductions numeric;refund_value numeric;latest_water numeric;latest_electric numeric;deduction_id uuid;refund_id uuid;
begin
  select * into mo from public.move_outs where id=target_move_out_id for update;if mo.id is null then raise exception 'MOVE_OUT_NOT_FOUND';end if;
  select * into c from public.contracts where id=mo.contract_id for update;
  if not public.has_org_permission(mo.organization_id,'move_outs.manage') or not public.has_org_permission(mo.organization_id,'deposits.manage') then raise exception 'FORBIDDEN';end if;
  if mo.status not in ('notice_received','inspection_scheduled','pending_settlement') then raise exception 'MOVE_OUT_CANNOT_COMPLETE';end if;
  if target_actual_date<mo.notice_date or least(target_final_water,target_final_electric,target_damage,target_cleaning,target_utility,target_other)<0 then raise exception 'INVALID_MOVE_OUT_DATA';end if;
  select coalesce(max(mr.current_reading) filter(where m.meter_type='water'),0),coalesce(max(mr.current_reading) filter(where m.meter_type='electricity'),0) into latest_water,latest_electric from public.meters m left join public.meter_readings mr on mr.meter_id=m.id where m.room_id=mo.room_id;
  if target_final_water<latest_water or target_final_electric<latest_electric then raise exception 'FINAL_METER_DECREASED';end if;
  select coalesce(sum(case when direction='in' then amount else -amount end),0) into deposit_balance from public.deposit_transactions where contract_id=mo.contract_id;
  select coalesce(sum(balance),0) into outstanding from public.invoices where room_id=mo.room_id and tenant_id=mo.tenant_id and status not in ('cancelled','written_off','paid');
  deductions:=round(target_damage+target_cleaning+target_utility+target_other,2);refund_value:=deposit_balance-deductions;
  update public.move_outs set actual_move_out_date=target_actual_date,final_water_reading=target_final_water,final_electric_reading=target_final_electric,damage_amount=target_damage,cleaning_fee=target_cleaning,utility_charge=target_utility,other_deduction=target_other,deposit_balance_snapshot=deposit_balance,total_deduction=deductions,refund_amount=greatest(refund_value,0),outstanding_invoice_balance=outstanding,inspection_notes=nullif(trim(target_inspection_notes),''),internal_notes=nullif(trim(target_internal_notes),''),status=case when outstanding>0 or refund_value<0 then 'pending_settlement' else 'completed' end,completed_by=case when outstanding=0 and refund_value>=0 then auth.uid() else null end,completed_at=case when outstanding=0 and refund_value>=0 then now() else null end,updated_at=now(),version=version+1 where id=mo.id;
  if outstanding>0 then return jsonb_build_object('completed',false,'reason','OUTSTANDING_INVOICES','outstanding',outstanding,'deposit_balance',deposit_balance,'deductions',deductions);end if;
  if refund_value<0 then return jsonb_build_object('completed',false,'reason','DEDUCTION_EXCEEDS_DEPOSIT','shortfall',abs(refund_value),'deposit_balance',deposit_balance,'deductions',deductions);end if;
  if deductions>0 then insert into public.deposit_transactions(organization_id,dormitory_id,contract_id,tenant_id,move_out_id,transaction_type,direction,amount,currency,transaction_date,notes,idempotency_key,approved_by)
    values(mo.organization_id,mo.dormitory_id,mo.contract_id,mo.tenant_id,mo.id,'deduction','out',deductions,'THB',now(),'หักค่าใช้จ่ายเมื่อย้ายออก','moveout:deduction:'||mo.id,auth.uid()) returning id into deduction_id;
    insert into public.financial_ledger(organization_id,dormitory_id,transaction_type,entity_id,debit,credit,currency) values(mo.organization_id,mo.dormitory_id,'adjustment',deduction_id,0,deductions,'THB');end if;
  if refund_value>0 then insert into public.deposit_transactions(organization_id,dormitory_id,contract_id,tenant_id,move_out_id,transaction_type,direction,amount,currency,transaction_date,notes,idempotency_key,approved_by)
    values(mo.organization_id,mo.dormitory_id,mo.contract_id,mo.tenant_id,mo.id,'refund','out',refund_value,'THB',now(),'คืนเงินประกันเมื่อย้ายออก','moveout:refund:'||mo.id,auth.uid()) returning id into refund_id;
    insert into public.financial_ledger(organization_id,dormitory_id,transaction_type,entity_id,debit,credit,currency) values(mo.organization_id,mo.dormitory_id,'refund',refund_id,refund_value,0,'THB');end if;
  update public.contracts set status='expired',updated_at=now(),version=version+1 where id=c.id;
  update public.rooms set status='cleaning',updated_at=now(),version=version+1 where id=mo.room_id;
  insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,before_data,after_data) values(mo.organization_id,mo.dormitory_id,auth.uid(),'move_out.complete','move_out',mo.id,jsonb_build_object('status',mo.status),jsonb_build_object('status','completed','deposit_balance',deposit_balance,'deductions',deductions,'refund',refund_value));
  return jsonb_build_object('completed',true,'deposit_balance',deposit_balance,'deductions',deductions,'refund',refund_value);
end $$;

create or replace function public.mark_move_out_room_ready(target_move_out_id uuid) returns text language plpgsql security definer set search_path='' as $$
declare mo public.move_outs%rowtype;room_no text;
begin select * into mo from public.move_outs where id=target_move_out_id;if mo.id is null or mo.status<>'completed' then raise exception 'MOVE_OUT_NOT_COMPLETED';end if;if not public.has_org_permission(mo.organization_id,'move_outs.manage') then raise exception 'FORBIDDEN';end if;
  update public.rooms set status='vacant',updated_at=now(),version=version+1 where id=mo.room_id and status='cleaning' returning room_number into room_no;if room_no is null then raise exception 'ROOM_NOT_CLEANING';end if;
  insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data) values(mo.organization_id,mo.dormitory_id,auth.uid(),'move_out.room_ready','room',mo.room_id,jsonb_build_object('status','vacant','move_out_id',mo.id));return room_no;end $$;

revoke all on function public.record_deposit_receipt(uuid,numeric,timestamptz,text,text,text,text),public.request_move_out(uuid,date,date,date,text),public.complete_move_out(uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text),public.mark_move_out_room_ready(uuid) from public,anon;
grant execute on function public.record_deposit_receipt(uuid,numeric,timestamptz,text,text,text,text),public.request_move_out(uuid,date,date,date,text),public.complete_move_out(uuid,date,numeric,numeric,numeric,numeric,numeric,numeric,text,text),public.mark_move_out_room_ready(uuid) to authenticated;
commit;
