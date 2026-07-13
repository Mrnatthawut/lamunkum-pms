begin;

insert into public.permissions(code,description) values
('meters.read','ดูมิเตอร์และประวัติ'),('meters.record','บันทึกค่ามิเตอร์'),('meters.manage_rates','จัดการอัตราค่าน้ำไฟ') on conflict do nothing;
insert into public.role_permissions(role,permission_id)
select role_name,p.id from unnest(array['super_admin','owner','manager']::public.app_role[]) role_name cross join public.permissions p where p.code like 'meters.%' on conflict do nothing;
insert into public.role_permissions(role,permission_id)
select role_name,p.id from unnest(array['staff']::public.app_role[]) role_name cross join public.permissions p where p.code in ('meters.read','meters.record') on conflict do nothing;
insert into public.role_permissions(role,permission_id)
select role_name,p.id from unnest(array['accountant']::public.app_role[]) role_name cross join public.permissions p where p.code='meters.read' on conflict do nothing;

alter table public.meters
  add column if not exists installed_at date not null default (timezone('Asia/Bangkok',now()))::date,
  add column if not exists status text not null default 'active' check(status in ('active','inactive','replaced','maintenance')),
  add column if not exists rollover_max numeric(16,3) check(rollover_max>0), add column if not exists notes text,
  add column if not exists updated_at timestamptz not null default now(), add column if not exists version integer not null default 1;

alter table public.meter_readings drop constraint if exists meter_readings_check;
alter table public.meter_readings drop column if exists units;
alter table public.meter_readings add column units numeric(16,3) not null default 0 check(units>=0);
update public.meter_readings set units=case when meter_replaced then current_reading else current_reading-previous_reading end;
alter table public.meter_readings alter column units drop default;
alter table public.meter_readings
  add column if not exists read_at timestamptz not null default now(), add column if not exists meter_rollover boolean not null default false,
  add column if not exists unit_price numeric(14,4) check(unit_price>=0), add column if not exists total_amount numeric(14,2) not null default 0 check(total_amount>=0),
  add column if not exists rate_plan_id uuid, add column if not exists rate_snapshot jsonb not null default '{}'::jsonb,
  add column if not exists image_path text, add column if not exists notes text, add column if not exists is_anomaly boolean not null default false,
  add column if not exists anomaly_reason text, add column if not exists updated_at timestamptz not null default now(), add column if not exists version integer not null default 1,
  add constraint meter_reading_flags_check check(not(meter_replaced and meter_rollover));

create table public.utility_rate_plans (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  dormitory_id uuid not null references public.dormitories(id) on delete restrict, name text not null,
  meter_type text not null check(meter_type in ('water','electricity','other')), pricing_type text not null check(pricing_type in ('fixed','tiered')),
  price_per_unit numeric(14,4) check(price_per_unit>=0), minimum_charge numeric(14,2) not null default 0 check(minimum_charge>=0),
  effective_from date not null, effective_to date, active boolean not null default true,
  created_by uuid references public.profiles(id) on delete restrict, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), version integer not null default 1,
  check(effective_to is null or effective_to>=effective_from), check((pricing_type='fixed' and price_per_unit is not null) or pricing_type='tiered')
);
create index utility_rates_effective_idx on public.utility_rate_plans(dormitory_id,meter_type,effective_from desc) where active;
create unique index utility_rates_effective_unique on public.utility_rate_plans(dormitory_id,meter_type,effective_from);
create table public.utility_rate_tiers (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  rate_plan_id uuid not null references public.utility_rate_plans(id) on delete restrict, tier_order integer not null check(tier_order>0),
  from_unit numeric(16,3) not null check(from_unit>=0), to_unit numeric(16,3), price_per_unit numeric(14,4) not null check(price_per_unit>=0),
  check(to_unit is null or to_unit>from_unit), unique(rate_plan_id,tier_order), unique(rate_plan_id,from_unit)
);
alter table public.meter_readings add constraint meter_readings_rate_plan_fkey foreign key(rate_plan_id) references public.utility_rate_plans(id) on delete restrict;

alter table public.utility_rate_plans enable row level security; alter table public.utility_rate_tiers enable row level security;
drop policy if exists meter_member_read on public.meters; drop policy if exists meter_reading_member_read on public.meter_readings;
create policy meter_member_read on public.meters for select using(public.has_org_permission(organization_id,'meters.read'));
create policy meter_member_create on public.meters for insert with check(public.has_org_permission(organization_id,'meters.record'));
create policy meter_member_update on public.meters for update using(public.has_org_permission(organization_id,'meters.record')) with check(public.has_org_permission(organization_id,'meters.record'));
create policy meter_reading_member_read on public.meter_readings for select using(public.has_org_permission(organization_id,'meters.read'));
create policy rate_plan_member_read on public.utility_rate_plans for select using(public.has_org_permission(organization_id,'meters.read'));
create policy rate_plan_member_write on public.utility_rate_plans for insert with check(public.has_org_permission(organization_id,'meters.manage_rates'));
create policy rate_plan_member_update on public.utility_rate_plans for update using(public.has_org_permission(organization_id,'meters.manage_rates')) with check(public.has_org_permission(organization_id,'meters.manage_rates'));
create policy rate_tier_member_read on public.utility_rate_tiers for select using(public.has_org_permission(organization_id,'meters.read'));
create policy rate_tier_member_write on public.utility_rate_tiers for insert with check(public.has_org_permission(organization_id,'meters.manage_rates'));
grant select,insert,update on public.meters to authenticated; grant select on public.meter_readings to authenticated;
grant select,insert,update on public.utility_rate_plans to authenticated; grant select,insert on public.utility_rate_tiers to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
('meter-images','meter-images',false,5242880,array['image/png','image/jpeg','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
create or replace function public.can_manage_meter_storage(object_name text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.organization_members m join public.role_permissions rp on rp.role=m.role join public.permissions p on p.id=rp.permission_id
    where m.profile_id=auth.uid() and m.active and m.organization_id::text=split_part(object_name,'/',1) and p.code='meters.record')
$$;
revoke all on function public.can_manage_meter_storage(text) from public,anon; grant execute on function public.can_manage_meter_storage(text) to authenticated;
create policy meter_image_insert on storage.objects for insert to authenticated with check(bucket_id='meter-images' and public.can_manage_meter_storage(name));
create policy meter_image_read on storage.objects for select to authenticated using(bucket_id='meter-images' and (public.can_manage_meter_storage(name) or public.can_manage_storage_org(name)));
create policy meter_image_delete on storage.objects for delete to authenticated using(bucket_id='meter-images' and public.can_manage_meter_storage(name));

create or replace function public.create_room_meter(target_dormitory_id uuid,target_room_id uuid,target_meter_type text,target_meter_number text,target_initial_reading numeric,target_rollover_max numeric,target_notes text)
returns uuid language plpgsql security definer set search_path='' as $$
declare target_org_id uuid;new_id uuid;
begin
  select organization_id into target_org_id from public.rooms where id=target_room_id and dormitory_id=target_dormitory_id and deleted_at is null;
  if target_org_id is null then raise exception 'ROOM_NOT_FOUND'; end if;
  if not public.has_org_permission(target_org_id,'meters.record') then raise exception 'FORBIDDEN'; end if;
  if target_meter_type not in ('water','electricity','other') or length(trim(target_meter_number))<2 or target_initial_reading<0 or (target_rollover_max is not null and target_rollover_max<=target_initial_reading) then raise exception 'INVALID_METER'; end if;
  insert into public.meters(organization_id,dormitory_id,room_id,meter_number,meter_type,initial_reading,rollover_max,notes)
  values(target_org_id,target_dormitory_id,target_room_id,upper(trim(target_meter_number)),target_meter_type,target_initial_reading,target_rollover_max,nullif(trim(target_notes),'')) returning id into new_id;
  update public.rooms set water_meter_number=case when target_meter_type='water' then upper(trim(target_meter_number)) else water_meter_number end,
    electric_meter_number=case when target_meter_type='electricity' then upper(trim(target_meter_number)) else electric_meter_number end,updated_at=now(),version=version+1 where id=target_room_id;
  insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data)
  values(target_org_id,target_dormitory_id,auth.uid(),'meter.create','meter',new_id,jsonb_build_object('room_id',target_room_id,'meter_type',target_meter_type,'meter_number',upper(trim(target_meter_number))));
  return new_id;
end $$;

create or replace function public.create_utility_rate_plan(target_dormitory_id uuid,target_name text,target_meter_type text,target_pricing_type text,target_price_per_unit numeric,target_minimum_charge numeric,target_effective_from date,target_tiers jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare target_org_id uuid;new_id uuid;tier jsonb;expected_from numeric:=0;tier_count integer:=0;
begin
  select organization_id into target_org_id from public.dormitories where id=target_dormitory_id and deleted_at is null;
  if target_org_id is null then raise exception 'DORMITORY_NOT_FOUND'; end if;
  if not public.has_org_permission(target_org_id,'meters.manage_rates') then raise exception 'FORBIDDEN'; end if;
  if target_meter_type not in ('water','electricity','other') or target_pricing_type not in ('fixed','tiered') or length(trim(target_name))<2 or target_minimum_charge<0 then raise exception 'INVALID_RATE'; end if;
  if target_pricing_type='fixed' and (target_price_per_unit is null or target_price_per_unit<0) then raise exception 'INVALID_RATE'; end if;
  if target_pricing_type='tiered' and (jsonb_typeof(target_tiers)<>'array' or jsonb_array_length(target_tiers)<1) then raise exception 'INVALID_TIERS'; end if;
  update public.utility_rate_plans set active=false,effective_to=target_effective_from-1,updated_at=now(),version=version+1
    where dormitory_id=target_dormitory_id and meter_type=target_meter_type and active and effective_from<target_effective_from;
  insert into public.utility_rate_plans(organization_id,dormitory_id,name,meter_type,pricing_type,price_per_unit,minimum_charge,effective_from,created_by)
  values(target_org_id,target_dormitory_id,trim(target_name),target_meter_type,target_pricing_type,case when target_pricing_type='fixed' then target_price_per_unit else null end,target_minimum_charge,target_effective_from,auth.uid()) returning id into new_id;
  if target_pricing_type='tiered' then
    for tier in select * from jsonb_array_elements(target_tiers) loop tier_count:=tier_count+1;
      if (tier->>'fromUnit')::numeric<>expected_from or (tier->>'pricePerUnit')::numeric<0 or ((tier->>'toUnit') is not null and (tier->>'toUnit')<>'' and (tier->>'toUnit')::numeric<=expected_from) then raise exception 'INVALID_TIERS'; end if;
      insert into public.utility_rate_tiers(organization_id,rate_plan_id,tier_order,from_unit,to_unit,price_per_unit)
      values(target_org_id,new_id,tier_count,expected_from,case when coalesce(tier->>'toUnit','')='' then null else (tier->>'toUnit')::numeric end,(tier->>'pricePerUnit')::numeric);
      if coalesce(tier->>'toUnit','')='' then expected_from:=-1; else expected_from:=(tier->>'toUnit')::numeric; end if;
      if expected_from=-1 and tier_count<jsonb_array_length(target_tiers) then raise exception 'INVALID_TIERS'; end if;
    end loop;
    if expected_from<>-1 then raise exception 'INVALID_TIERS'; end if;
  end if;
  insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data)
  values(target_org_id,target_dormitory_id,auth.uid(),'utility_rate.create','utility_rate_plan',new_id,jsonb_build_object('meter_type',target_meter_type,'pricing_type',target_pricing_type,'effective_from',target_effective_from));
  return new_id;
end $$;

create or replace function public.record_meter_reading(target_meter_id uuid,target_billing_month date,target_current_reading numeric,target_meter_replaced boolean,target_meter_rollover boolean,target_image_path text,target_notes text)
returns uuid language plpgsql security definer set search_path='' as $$
declare m public.meters%rowtype;previous_value numeric;calculated_units numeric;rate public.utility_rate_plans%rowtype;calculated_total numeric:=0;new_id uuid;average_units numeric;rate_data jsonb;tier record;
begin
  select * into m from public.meters where id=target_meter_id and active and status='active' for update;
  if m.id is null then raise exception 'METER_NOT_FOUND'; end if;
  if not public.has_org_permission(m.organization_id,'meters.record') then raise exception 'FORBIDDEN'; end if;
  if date_trunc('month',target_billing_month)::date<>target_billing_month or target_current_reading<0 or (target_meter_replaced and target_meter_rollover) then raise exception 'INVALID_READING'; end if;
  select current_reading into previous_value from public.meter_readings where meter_id=m.id and billing_month<target_billing_month order by billing_month desc limit 1;
  previous_value:=coalesce(previous_value,m.initial_reading);
  if target_meter_replaced then calculated_units:=target_current_reading;
  elsif target_meter_rollover then
    if m.rollover_max is null or target_current_reading>m.rollover_max or previous_value>m.rollover_max then raise exception 'INVALID_ROLLOVER'; end if;
    calculated_units:=(m.rollover_max-previous_value)+target_current_reading;
  else
    if target_current_reading<previous_value then raise exception 'METER_READING_DECREASED'; end if; calculated_units:=target_current_reading-previous_value;
  end if;
  select * into rate from public.utility_rate_plans where dormitory_id=m.dormitory_id and meter_type=m.meter_type and active
    and effective_from<=target_billing_month and (effective_to is null or effective_to>=target_billing_month) order by effective_from desc limit 1;
  if rate.id is null then raise exception 'RATE_NOT_FOUND'; end if;
  if rate.pricing_type='fixed' then calculated_total:=calculated_units*rate.price_per_unit;
  else for tier in select * from public.utility_rate_tiers where rate_plan_id=rate.id order by tier_order loop
    calculated_total:=calculated_total+greatest(least(calculated_units,coalesce(tier.to_unit,calculated_units))-tier.from_unit,0)*tier.price_per_unit;
  end loop; end if;
  calculated_total:=round(greatest(calculated_total,rate.minimum_charge),2);
  select avg(units) into average_units from (select units from public.meter_readings where meter_id=m.id order by billing_month desc limit 3) recent;
  rate_data:=jsonb_build_object('id',rate.id,'name',rate.name,'pricing_type',rate.pricing_type,'price_per_unit',rate.price_per_unit,'minimum_charge',rate.minimum_charge,'effective_from',rate.effective_from);
  if target_image_path is not null and (left(target_image_path,length(m.organization_id::text||'/'||m.dormitory_id::text||'/meters/'||m.id::text||'/'))<>m.organization_id::text||'/'||m.dormitory_id::text||'/meters/'||m.id::text||'/' or target_image_path like '%..%') then raise exception 'INVALID_STORAGE_PATH'; end if;
  insert into public.meter_readings(organization_id,dormitory_id,meter_id,billing_month,previous_reading,current_reading,units,meter_replaced,meter_rollover,
    unit_price,total_amount,rate_plan_id,rate_snapshot,image_path,notes,is_anomaly,anomaly_reason,created_by)
  values(m.organization_id,m.dormitory_id,m.id,target_billing_month,previous_value,target_current_reading,calculated_units,target_meter_replaced,target_meter_rollover,
    case when rate.pricing_type='fixed' then rate.price_per_unit else null end,calculated_total,rate.id,rate_data,target_image_path,nullif(trim(target_notes),''),
    target_current_reading=0 or (average_units>0 and calculated_units>average_units*2 and calculated_units>10),case when target_current_reading=0 then 'ค่าปัจจุบันเป็นศูนย์' when average_units>0 and calculated_units>average_units*2 and calculated_units>10 then 'ใช้สูงกว่าค่าเฉลี่ยมากกว่า 2 เท่า' else null end,auth.uid()) returning id into new_id;
  insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data)
  values(m.organization_id,m.dormitory_id,auth.uid(),'meter_reading.create','meter_reading',new_id,jsonb_build_object('meter_id',m.id,'billing_month',target_billing_month,'previous',previous_value,'current',target_current_reading,'units',calculated_units,'total',calculated_total));
  return new_id;
end $$;

revoke all on function public.create_room_meter(uuid,uuid,text,text,numeric,numeric,text),public.create_utility_rate_plan(uuid,text,text,text,numeric,numeric,date,jsonb),public.record_meter_reading(uuid,date,numeric,boolean,boolean,text,text) from public,anon;
grant execute on function public.create_room_meter(uuid,uuid,text,text,numeric,numeric,text),public.create_utility_rate_plan(uuid,text,text,text,numeric,numeric,date,jsonb),public.record_meter_reading(uuid,date,numeric,boolean,boolean,text,text) to authenticated;

insert into public.utility_rate_plans(organization_id,dormitory_id,name,meter_type,pricing_type,price_per_unit,minimum_charge,effective_from)
select d.organization_id,d.id,'ค่าไฟมาตรฐาน','electricity','fixed',8,0,'2020-01-01' from public.dormitories d where d.deleted_at is null and not exists(select 1 from public.utility_rate_plans r where r.dormitory_id=d.id and r.meter_type='electricity');
insert into public.utility_rate_plans(organization_id,dormitory_id,name,meter_type,pricing_type,price_per_unit,minimum_charge,effective_from)
select d.organization_id,d.id,'ค่าน้ำมาตรฐาน','water','fixed',18,100,'2020-01-01' from public.dormitories d where d.deleted_at is null and not exists(select 1 from public.utility_rate_plans r where r.dormitory_id=d.id and r.meter_type='water');

commit;
