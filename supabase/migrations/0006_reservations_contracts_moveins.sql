begin;

create table public.reservations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  dormitory_id uuid not null references public.dormitories(id) on delete restrict,
  room_id uuid not null references public.rooms(id) on delete restrict,
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  reservation_number text not null,
  reservation_date date not null default (timezone('Asia/Bangkok', now()))::date,
  expected_move_in_date date not null,
  booking_amount numeric(14,2) not null default 0 check(booking_amount >= 0),
  currency char(3) not null default 'THB',
  payment_method text,
  expires_at timestamptz not null,
  status text not null check(status in ('pending_payment','confirmed','cancelled','expired','converted')),
  notes text,
  created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  unique(organization_id, reservation_number)
);
create unique index one_open_reservation_per_room on public.reservations(room_id) where status in ('pending_payment','confirmed');
create index reservations_dormitory_status_idx on public.reservations(dormitory_id, status, expected_move_in_date);

alter table public.contracts
  add column if not exists contract_date date not null default (timezone('Asia/Bangkok', now()))::date,
  add column if not exists advance_rent numeric(14,2) not null default 0 check(advance_rent >= 0),
  add column if not exists due_day smallint not null default 5 check(due_day between 1 and 28),
  add column if not exists notice_days integer not null default 30 check(notice_days >= 0),
  add column if not exists notes text,
  add column if not exists reservation_id uuid references public.reservations(id) on delete restrict,
  add column if not exists created_by uuid references public.profiles(id) on delete restrict;

create table public.move_ins (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  dormitory_id uuid not null references public.dormitories(id) on delete restrict,
  contract_id uuid not null unique references public.contracts(id) on delete restrict,
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  room_id uuid not null references public.rooms(id) on delete restrict,
  move_in_date date not null,
  initial_water_reading numeric(16,3) not null default 0 check(initial_water_reading >= 0),
  initial_electric_reading numeric(16,3) not null default 0 check(initial_electric_reading >= 0),
  inspection_notes text,
  created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1
);
create index move_ins_room_date_idx on public.move_ins(room_id, move_in_date desc);

alter table public.reservations enable row level security;
alter table public.move_ins enable row level security;

create policy reservation_member_read on public.reservations for select
  using(public.has_org_permission(organization_id,'contracts.manage') or public.is_tenant_of(tenant_id));
create policy reservation_member_create on public.reservations for insert
  with check(public.has_org_permission(organization_id,'contracts.manage'));
create policy reservation_member_update on public.reservations for update
  using(public.has_org_permission(organization_id,'contracts.manage'))
  with check(public.has_org_permission(organization_id,'contracts.manage'));
create policy move_in_member_read on public.move_ins for select
  using(public.has_org_permission(organization_id,'contracts.manage') or public.is_tenant_of(tenant_id));
create policy move_in_member_create on public.move_ins for insert
  with check(public.has_org_permission(organization_id,'contracts.manage'));

drop policy if exists contract_staff_scope on public.contracts;
create policy contract_member_read on public.contracts for select
  using(public.has_org_permission(organization_id,'contracts.manage') or public.is_tenant_of(tenant_id));
create policy contract_member_create on public.contracts for insert
  with check(public.has_org_permission(organization_id,'contracts.manage'));
create policy contract_member_update on public.contracts for update
  using(public.has_org_permission(organization_id,'contracts.manage'))
  with check(public.has_org_permission(organization_id,'contracts.manage'));

grant select, insert, update on public.reservations, public.contracts, public.move_ins to authenticated;

create or replace function public.create_reservation(
  target_dormitory_id uuid, target_room_id uuid, target_tenant_id uuid,
  target_expected_move_in_date date, target_booking_amount numeric,
  target_payment_method text, target_expires_at timestamptz,
  target_status text, target_notes text
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_org_id uuid; room_state public.room_status; tenant_org_id uuid;
  sequence_value bigint; sequence_period text; generated_number text; new_id uuid;
begin
  select organization_id,status into target_org_id,room_state
  from public.rooms where id=target_room_id and dormitory_id=target_dormitory_id and deleted_at is null and active
  for update;
  if target_org_id is null then raise exception 'ROOM_NOT_FOUND'; end if;
  if not public.has_org_permission(target_org_id,'contracts.manage') then raise exception 'FORBIDDEN'; end if;
  if room_state <> 'vacant' then raise exception 'ROOM_NOT_AVAILABLE'; end if;
  select organization_id into tenant_org_id from public.tenants
  where id=target_tenant_id and dormitory_id=target_dormitory_id and deleted_at is null and status='active';
  if tenant_org_id is distinct from target_org_id then raise exception 'TENANT_MISMATCH'; end if;
  if target_status not in ('pending_payment','confirmed') then raise exception 'INVALID_STATUS'; end if;
  if target_expected_move_in_date < (timezone('Asia/Bangkok',now()))::date then raise exception 'INVALID_MOVE_IN_DATE'; end if;
  if target_expires_at <= now() then raise exception 'INVALID_EXPIRY'; end if;
  if target_booking_amount < 0 then raise exception 'INVALID_AMOUNT'; end if;

  sequence_period := to_char(timezone('Asia/Bangkok',now()),'YYYY');
  insert into public.document_sequences(organization_id,dormitory_id,document_type,period,current_value,prefix)
  values(target_org_id,target_dormitory_id,'reservation',sequence_period,1,'RES')
  on conflict(organization_id,dormitory_id,document_type,period)
  do update set current_value=public.document_sequences.current_value+1,updated_at=now()
  returning current_value into sequence_value;
  generated_number := 'RES-'||sequence_period||'-'||lpad(sequence_value::text,4,'0');

  insert into public.reservations(organization_id,dormitory_id,room_id,tenant_id,reservation_number,
    expected_move_in_date,booking_amount,payment_method,expires_at,status,notes,created_by)
  values(target_org_id,target_dormitory_id,target_room_id,target_tenant_id,generated_number,
    target_expected_move_in_date,target_booking_amount,nullif(trim(target_payment_method),''),target_expires_at,
    target_status,nullif(trim(target_notes),''),auth.uid()) returning id into new_id;
  update public.rooms set status='reserved',updated_at=now(),version=version+1 where id=target_room_id;
  insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data)
  values(target_org_id,target_dormitory_id,auth.uid(),'reservation.create','reservation',new_id,
    jsonb_build_object('reservation_number',generated_number,'room_id',target_room_id,'tenant_id',target_tenant_id,'status',target_status));
  return new_id;
end;
$$;

create or replace function public.set_reservation_status(target_reservation_id uuid, target_status text, target_reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare item public.reservations%rowtype;
begin
  select * into item from public.reservations where id=target_reservation_id for update;
  if item.id is null then raise exception 'RESERVATION_NOT_FOUND'; end if;
  if not public.has_org_permission(item.organization_id,'contracts.manage') then raise exception 'FORBIDDEN'; end if;
  if target_status='confirmed' and item.status='pending_payment' then
    update public.reservations set status='confirmed',updated_at=now(),version=version+1 where id=item.id;
  elsif target_status='cancelled' and item.status in ('pending_payment','confirmed') then
    update public.reservations set status='cancelled',notes=concat_ws(E'\n',notes,nullif(trim(target_reason),'')),updated_at=now(),version=version+1 where id=item.id;
    update public.rooms set status='vacant',updated_at=now(),version=version+1 where id=item.room_id and status='reserved';
  else raise exception 'INVALID_STATUS_TRANSITION';
  end if;
  insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,before_data,after_data)
  values(item.organization_id,item.dormitory_id,auth.uid(),'reservation.status_change','reservation',item.id,
    jsonb_build_object('status',item.status),jsonb_build_object('status',target_status,'reason',nullif(trim(target_reason),'')));
end;
$$;

create or replace function public.create_active_contract_and_move_in(
  target_dormitory_id uuid, target_room_id uuid, target_tenant_id uuid, target_reservation_id uuid,
  target_contract_date date, target_start_date date, target_end_date date,
  target_monthly_rent numeric, target_deposit numeric, target_advance_rent numeric,
  target_due_day integer, target_notice_days integer,
  target_initial_water numeric, target_initial_electric numeric,
  target_inspection_notes text, target_notes text
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  target_org_id uuid; room_state public.room_status; tenant_org_id uuid; reservation_item public.reservations%rowtype;
  sequence_value bigint; sequence_period text; generated_number text; new_contract_id uuid;
begin
  select organization_id,status into target_org_id,room_state from public.rooms
  where id=target_room_id and dormitory_id=target_dormitory_id and deleted_at is null and active for update;
  if target_org_id is null then raise exception 'ROOM_NOT_FOUND'; end if;
  if not public.has_org_permission(target_org_id,'contracts.manage') then raise exception 'FORBIDDEN'; end if;
  select organization_id into tenant_org_id from public.tenants
  where id=target_tenant_id and dormitory_id=target_dormitory_id and deleted_at is null and status='active';
  if tenant_org_id is distinct from target_org_id then raise exception 'TENANT_MISMATCH'; end if;

  if target_reservation_id is not null then
    select * into reservation_item from public.reservations where id=target_reservation_id for update;
    if reservation_item.id is null or reservation_item.room_id<>target_room_id or reservation_item.tenant_id<>target_tenant_id then raise exception 'RESERVATION_MISMATCH'; end if;
    if reservation_item.status<>'confirmed' then raise exception 'RESERVATION_NOT_CONFIRMED'; end if;
    if room_state<>'reserved' then raise exception 'ROOM_NOT_AVAILABLE'; end if;
  elsif room_state<>'vacant' then raise exception 'ROOM_NOT_AVAILABLE';
  end if;
  if target_end_date<=target_start_date or target_contract_date>target_start_date then raise exception 'INVALID_CONTRACT_DATES'; end if;
  if target_monthly_rent<0 or target_deposit<0 or target_advance_rent<0 or target_initial_water<0 or target_initial_electric<0 then raise exception 'INVALID_AMOUNT'; end if;
  if target_due_day not between 1 and 28 or target_notice_days<0 then raise exception 'INVALID_TERMS'; end if;

  sequence_period := to_char(timezone('Asia/Bangkok',now()),'YYYY');
  insert into public.document_sequences(organization_id,dormitory_id,document_type,period,current_value,prefix)
  values(target_org_id,target_dormitory_id,'contract',sequence_period,1,'CTR')
  on conflict(organization_id,dormitory_id,document_type,period)
  do update set current_value=public.document_sequences.current_value+1,updated_at=now()
  returning current_value into sequence_value;
  generated_number := 'CTR-'||sequence_period||'-'||lpad(sequence_value::text,4,'0');

  insert into public.contracts(organization_id,dormitory_id,tenant_id,room_id,contract_number,contract_date,start_date,end_date,
    monthly_rent,deposit,advance_rent,due_day,notice_days,status,notes,reservation_id,created_by)
  values(target_org_id,target_dormitory_id,target_tenant_id,target_room_id,generated_number,target_contract_date,target_start_date,target_end_date,
    target_monthly_rent,target_deposit,target_advance_rent,target_due_day,target_notice_days,'active',nullif(trim(target_notes),''),target_reservation_id,auth.uid())
  returning id into new_contract_id;
  insert into public.move_ins(organization_id,dormitory_id,contract_id,tenant_id,room_id,move_in_date,
    initial_water_reading,initial_electric_reading,inspection_notes,created_by)
  values(target_org_id,target_dormitory_id,new_contract_id,target_tenant_id,target_room_id,target_start_date,
    target_initial_water,target_initial_electric,nullif(trim(target_inspection_notes),''),auth.uid());
  update public.rooms set status='occupied',updated_at=now(),version=version+1 where id=target_room_id;
  if target_reservation_id is not null then
    update public.reservations set status='converted',updated_at=now(),version=version+1 where id=target_reservation_id;
  end if;
  insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data)
  values(target_org_id,target_dormitory_id,auth.uid(),'contract.activate','contract',new_contract_id,
    jsonb_build_object('contract_number',generated_number,'room_id',target_room_id,'tenant_id',target_tenant_id,'start_date',target_start_date));
  return new_contract_id;
end;
$$;

revoke all on function public.create_reservation(uuid,uuid,uuid,date,numeric,text,timestamptz,text,text) from public,anon;
grant execute on function public.create_reservation(uuid,uuid,uuid,date,numeric,text,timestamptz,text,text) to authenticated;
revoke all on function public.set_reservation_status(uuid,text,text) from public,anon;
grant execute on function public.set_reservation_status(uuid,text,text) to authenticated;
revoke all on function public.create_active_contract_and_move_in(uuid,uuid,uuid,uuid,date,date,date,numeric,numeric,numeric,integer,integer,numeric,numeric,text,text) from public,anon;
grant execute on function public.create_active_contract_and_move_in(uuid,uuid,uuid,uuid,date,date,date,numeric,numeric,numeric,integer,integer,numeric,numeric,text,text) to authenticated;

commit;
