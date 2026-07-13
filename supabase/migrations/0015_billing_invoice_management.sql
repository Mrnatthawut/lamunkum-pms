begin;

create table if not exists public.service_charge_types (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  dormitory_id uuid not null references public.dormitories(id) on delete restrict,
  code text not null,
  name text not null,
  charge_type text not null default 'recurring' check (charge_type in ('recurring','one_time')),
  default_amount numeric(14,2) not null check (default_amount >= 0),
  tax_rate numeric(6,3) not null default 0 check (tax_rate between 0 and 100),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  unique(dormitory_id,code)
);

create table if not exists public.contract_service_charges (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  dormitory_id uuid not null references public.dormitories(id) on delete restrict,
  contract_id uuid not null references public.contracts(id) on delete restrict,
  service_charge_type_id uuid not null references public.service_charge_types(id) on delete restrict,
  amount numeric(14,2) check (amount is null or amount >= 0),
  effective_from date not null,
  effective_to date check (effective_to is null or effective_to >= effective_from),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  unique(contract_id,service_charge_type_id,effective_from)
);

alter table public.billing_cycles add column if not exists notes text;
alter table public.billing_cycles add column if not exists created_by uuid references public.profiles(id) on delete restrict;
alter table public.invoices add column if not exists approved_by uuid references public.profiles(id) on delete restrict;
alter table public.invoices add column if not exists approved_at timestamptz;

create index if not exists service_charge_types_active_idx on public.service_charge_types(dormitory_id,active);
create index if not exists contract_service_charges_cycle_idx on public.contract_service_charges(contract_id,effective_from,effective_to) where active;
create index if not exists invoice_items_invoice_idx on public.invoice_items(invoice_id);
create unique index if not exists one_invoice_ledger_entry on public.financial_ledger(entity_id) where transaction_type='invoice';

alter table public.service_charge_types enable row level security;
alter table public.contract_service_charges enable row level security;

drop policy if exists billing_cycle_staff_scope on public.billing_cycles;
create policy billing_cycle_staff_scope on public.billing_cycles for all
  using(public.is_member_of(organization_id) and public.has_permission('invoices.manage'))
  with check(public.is_member_of(organization_id) and public.has_permission('invoices.manage'));

drop policy if exists invoice_staff_scope on public.invoices;
create policy invoice_staff_scope on public.invoices for all
  using(public.is_member_of(organization_id) and public.has_permission('invoices.manage'))
  with check(public.is_member_of(organization_id) and public.has_permission('invoices.manage'));

drop policy if exists invoice_item_staff_scope on public.invoice_items;
create policy invoice_item_staff_scope on public.invoice_items for all
  using(public.is_member_of(organization_id) and public.has_permission('invoices.manage'))
  with check(public.is_member_of(organization_id) and public.has_permission('invoices.manage'));
drop policy if exists invoice_item_tenant_read on public.invoice_items;
create policy invoice_item_tenant_read on public.invoice_items for select using (
  exists(select 1 from public.invoices i where i.id=invoice_id and public.is_tenant_of(i.tenant_id))
);

create policy service_charge_staff_scope on public.service_charge_types for all
  using(public.is_member_of(organization_id) and public.has_permission('invoices.manage'))
  with check(public.is_member_of(organization_id) and public.has_permission('invoices.manage'));
create policy contract_charge_staff_scope on public.contract_service_charges for all
  using(public.is_member_of(organization_id) and public.has_permission('invoices.manage'))
  with check(public.is_member_of(organization_id) and public.has_permission('invoices.manage'));

grant select,insert,update on public.service_charge_types,public.contract_service_charges to authenticated;

create or replace function public.create_billing_cycle(
  target_dormitory_id uuid,target_billing_month date,target_period_start date,target_period_end date,
  target_issue_date date,target_due_date date,target_notes text
) returns uuid language plpgsql security definer set search_path='' as $$
declare target_org_id uuid; new_id uuid;
begin
  select organization_id into target_org_id from public.dormitories where id=target_dormitory_id and deleted_at is null;
  if target_org_id is null then raise exception 'DORMITORY_NOT_FOUND'; end if;
  if not public.has_org_permission(target_org_id,'invoices.manage') then raise exception 'FORBIDDEN'; end if;
  if date_trunc('month',target_billing_month)::date<>target_billing_month
    or target_period_end<target_period_start or target_issue_date<target_period_start or target_due_date<target_issue_date then
    raise exception 'INVALID_BILLING_CYCLE';
  end if;
  insert into public.billing_cycles(organization_id,dormitory_id,billing_month,period_start,period_end,issue_date,due_date,notes,created_by)
  values(target_org_id,target_dormitory_id,target_billing_month,target_period_start,target_period_end,target_issue_date,target_due_date,nullif(trim(target_notes),''),auth.uid())
  returning id into new_id;
  insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data)
  values(target_org_id,target_dormitory_id,auth.uid(),'billing_cycle.create','billing_cycle',new_id,jsonb_build_object('billing_month',target_billing_month,'due_date',target_due_date));
  return new_id;
end $$;

create or replace function public.create_service_charge_type(
  target_dormitory_id uuid,target_code text,target_name text,target_charge_type text,target_default_amount numeric,target_tax_rate numeric
) returns uuid language plpgsql security definer set search_path='' as $$
declare target_org_id uuid; new_id uuid;
begin
  select organization_id into target_org_id from public.dormitories where id=target_dormitory_id and deleted_at is null;
  if target_org_id is null then raise exception 'DORMITORY_NOT_FOUND'; end if;
  if not public.has_org_permission(target_org_id,'invoices.manage') then raise exception 'FORBIDDEN'; end if;
  if length(trim(target_code))<2 or length(trim(target_name))<2 or target_charge_type not in ('recurring','one_time')
    or target_default_amount<0 or target_tax_rate<0 or target_tax_rate>100 then raise exception 'INVALID_SERVICE_CHARGE'; end if;
  insert into public.service_charge_types(organization_id,dormitory_id,code,name,charge_type,default_amount,tax_rate)
  values(target_org_id,target_dormitory_id,upper(trim(target_code)),trim(target_name),target_charge_type,target_default_amount,target_tax_rate)
  returning id into new_id;
  insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data)
  values(target_org_id,target_dormitory_id,auth.uid(),'service_charge.create','service_charge_type',new_id,jsonb_build_object('code',upper(trim(target_code)),'amount',target_default_amount));
  return new_id;
end $$;

create or replace function public.assign_contract_service_charge(
  target_contract_id uuid,target_service_charge_type_id uuid,target_amount numeric,target_effective_from date,target_effective_to date
) returns uuid language plpgsql security definer set search_path='' as $$
declare c public.contracts%rowtype; s public.service_charge_types%rowtype; new_id uuid;
begin
  select * into c from public.contracts where id=target_contract_id;
  select * into s from public.service_charge_types where id=target_service_charge_type_id and active;
  if c.id is null or s.id is null or c.organization_id<>s.organization_id or c.dormitory_id<>s.dormitory_id then raise exception 'INVALID_SERVICE_ASSIGNMENT'; end if;
  if not public.has_org_permission(c.organization_id,'invoices.manage') then raise exception 'FORBIDDEN'; end if;
  if target_amount is not null and target_amount<0 or target_effective_to is not null and target_effective_to<target_effective_from then raise exception 'INVALID_SERVICE_ASSIGNMENT'; end if;
  insert into public.contract_service_charges(organization_id,dormitory_id,contract_id,service_charge_type_id,amount,effective_from,effective_to)
  values(c.organization_id,c.dormitory_id,c.id,s.id,target_amount,target_effective_from,target_effective_to) returning id into new_id;
  insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data)
  values(c.organization_id,c.dormitory_id,auth.uid(),'contract_service_charge.assign','contract_service_charge',new_id,jsonb_build_object('contract_id',c.id,'service_charge_type_id',s.id,'amount',coalesce(target_amount,s.default_amount)));
  return new_id;
end $$;

create or replace function public.generate_billing_cycle_invoices(target_billing_cycle_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare cycle public.billing_cycles%rowtype; c record; new_invoice_id uuid; sequence_value bigint; invoice_no text;
  subtotal_value numeric(14,2); tax_value numeric(14,2); generated_count integer:=0; skipped_count integer:=0; period_key text;
begin
  select * into cycle from public.billing_cycles where id=target_billing_cycle_id for update;
  if cycle.id is null then raise exception 'BILLING_CYCLE_NOT_FOUND'; end if;
  if not public.has_org_permission(cycle.organization_id,'invoices.manage') then raise exception 'FORBIDDEN'; end if;
  if cycle.status not in ('draft','review') then raise exception 'BILLING_CYCLE_LOCKED'; end if;
  period_key:=to_char(cycle.billing_month,'YYYYMM');
  for c in
    select c.*,t.id as bill_tenant_id from public.contracts c join public.tenants t on t.id=c.tenant_id and t.deleted_at is null
    where c.dormitory_id=cycle.dormitory_id and c.status in ('active','expiring')
      and c.start_date<=cycle.period_end and c.end_date>=cycle.period_start order by c.room_id
  loop
    if exists(select 1 from public.invoices i where i.billing_cycle_id=cycle.id and i.room_id=c.room_id and i.revision=1) then
      skipped_count:=skipped_count+1; continue;
    end if;
    insert into public.document_sequences(organization_id,dormitory_id,document_type,period,current_value,prefix)
    values(cycle.organization_id,cycle.dormitory_id,'invoice',period_key,1,'INV')
    on conflict(organization_id,dormitory_id,document_type,period)
    do update set current_value=public.document_sequences.current_value+1,updated_at=now()
    returning current_value into sequence_value;
    invoice_no:='INV-'||period_key||'-'||lpad(sequence_value::text,4,'0');
    insert into public.invoices(organization_id,dormitory_id,billing_cycle_id,room_id,tenant_id,invoice_number,issue_date,due_date,currency,total,balance,status)
    values(cycle.organization_id,cycle.dormitory_id,cycle.id,c.room_id,c.bill_tenant_id,invoice_no,cycle.issue_date,cycle.due_date,'THB',0,0,'pending_approval') returning id into new_invoice_id;

    insert into public.invoice_items(organization_id,invoice_id,code,description,quantity,unit,unit_price,discount,tax_rate,line_total)
    values(cycle.organization_id,new_invoice_id,'RENT','ค่าเช่าห้อง',1,'เดือน',c.monthly_rent,0,0,c.monthly_rent);

    insert into public.invoice_items(organization_id,invoice_id,code,description,quantity,unit,unit_price,discount,tax_rate,line_total)
    select cycle.organization_id,new_invoice_id,
      case m.meter_type when 'water' then 'WATER' when 'electricity' then 'ELECTRICITY' else 'UTILITY' end,
      case m.meter_type when 'water' then 'ค่าน้ำ' when 'electricity' then 'ค่าไฟ' else 'ค่าสาธารณูปโภค' end,
      mr.units,'หน่วย',case when mr.units>0 then round(mr.total_amount/mr.units,2) else 0 end,0,0,mr.total_amount
    from public.meters m join public.meter_readings mr on mr.meter_id=m.id
    where m.room_id=c.room_id and mr.billing_month=cycle.billing_month;

    insert into public.invoice_items(organization_id,invoice_id,code,description,quantity,unit,unit_price,discount,tax_rate,line_total)
    select cycle.organization_id,new_invoice_id,s.code,s.name,1,'รายการ',coalesce(cs.amount,s.default_amount),0,s.tax_rate,coalesce(cs.amount,s.default_amount)
    from public.contract_service_charges cs join public.service_charge_types s on s.id=cs.service_charge_type_id and s.active
    where cs.contract_id=c.id and cs.active and cs.effective_from<=cycle.period_end and (cs.effective_to is null or cs.effective_to>=cycle.period_start);

    select coalesce(sum(line_total-discount),0),coalesce(sum(round((line_total-discount)*tax_rate/100,2)),0)
      into subtotal_value,tax_value from public.invoice_items where invoice_id=new_invoice_id;
    update public.invoices set subtotal=subtotal_value,tax_total=tax_value,total=subtotal_value+tax_value,balance=subtotal_value+tax_value,updated_at=now()
      where id=new_invoice_id;
    insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data)
    values(cycle.organization_id,cycle.dormitory_id,auth.uid(),'invoice.generate','invoice',new_invoice_id,jsonb_build_object('invoice_number',invoice_no,'total',subtotal_value+tax_value));
    generated_count:=generated_count+1;
  end loop;
  update public.billing_cycles set status='review' where id=cycle.id and status='draft';
  return jsonb_build_object('generated',generated_count,'skipped',skipped_count);
end $$;

create or replace function public.approve_invoice(target_invoice_id uuid)
returns text language plpgsql security definer set search_path='' as $$
declare inv public.invoices%rowtype;
begin
  select * into inv from public.invoices where id=target_invoice_id for update;
  if inv.id is null then raise exception 'INVOICE_NOT_FOUND'; end if;
  if not public.has_org_permission(inv.organization_id,'invoices.manage') then raise exception 'FORBIDDEN'; end if;
  if inv.status='issued' then return inv.invoice_number; end if;
  if inv.status not in ('draft','pending_approval') then raise exception 'INVOICE_CANNOT_APPROVE'; end if;
  if inv.total<=0 then raise exception 'INVOICE_EMPTY'; end if;
  update public.invoices set status='issued',approved_by=auth.uid(),approved_at=now(),updated_at=now(),version=version+1 where id=inv.id;
  insert into public.financial_ledger(organization_id,dormitory_id,transaction_type,entity_id,debit,credit,currency,occurred_at)
  values(inv.organization_id,inv.dormitory_id,'invoice',inv.id,inv.total,0,inv.currency,now()) on conflict do nothing;
  update public.billing_cycles bc set status='open' where bc.id=inv.billing_cycle_id
    and not exists(select 1 from public.invoices i where i.billing_cycle_id=bc.id and i.status in ('draft','pending_approval'));
  insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,before_data,after_data)
  values(inv.organization_id,inv.dormitory_id,auth.uid(),'invoice.approve','invoice',inv.id,jsonb_build_object('status',inv.status),jsonb_build_object('status','issued','total',inv.total));
  return inv.invoice_number;
end $$;

revoke all on function public.create_billing_cycle(uuid,date,date,date,date,date,text),public.create_service_charge_type(uuid,text,text,text,numeric,numeric),public.assign_contract_service_charge(uuid,uuid,numeric,date,date),public.generate_billing_cycle_invoices(uuid),public.approve_invoice(uuid) from public,anon;
grant execute on function public.create_billing_cycle(uuid,date,date,date,date,date,text),public.create_service_charge_type(uuid,text,text,text,numeric,numeric),public.assign_contract_service_charge(uuid,uuid,numeric,date,date),public.generate_billing_cycle_invoices(uuid),public.approve_invoice(uuid) to authenticated;

commit;
