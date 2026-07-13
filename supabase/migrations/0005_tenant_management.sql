begin;

insert into public.permissions(code,description) values
('tenants.create','เพิ่มผู้เช่า'),('tenants.update','แก้ไขผู้เช่า'),('tenants.sensitive.read','ดูข้อมูลส่วนบุคคลสำคัญ')
on conflict do nothing;

insert into public.role_permissions(role, permission_id)
select role_name, p.id from unnest(array['super_admin','owner']::public.app_role[]) role_name
cross join public.permissions p where p.code like 'tenants.%' on conflict do nothing;
insert into public.role_permissions(role, permission_id)
select role_name, p.id from unnest(array['manager']::public.app_role[]) role_name
cross join public.permissions p where p.code = any(array['tenants.read','tenants.create','tenants.update','tenants.sensitive.read']) on conflict do nothing;
insert into public.role_permissions(role, permission_id)
select role_name, p.id from unnest(array['staff','accountant']::public.app_role[]) role_name
cross join public.permissions p where p.code = any(array['tenants.read','tenants.create','tenants.update']) on conflict do nothing;

alter table public.tenants
  add column if not exists id_type text not null default 'national_id' check(id_type in ('national_id','passport')),
  add column if not exists nickname text,
  add column if not exists birth_date date,
  add column if not exists registered_address text,
  add column if not exists current_address text,
  add column if not exists occupation text,
  add column if not exists workplace text,
  add column if not exists vehicle_registration text,
  add column if not exists notes text,
  add column if not exists line_display_name text,
  add column if not exists line_linked_at timestamptz;

create table public.tenant_occupants (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  dormitory_id uuid not null references public.dormitories(id) on delete restrict, tenant_id uuid not null references public.tenants(id) on delete restrict,
  relationship_type text not null check(relationship_type in ('co_occupant','guarantor')), title text, first_name text not null, last_name text not null,
  phone text, identity_encrypted text, identity_last4 char(4), notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz
);
create index tenant_occupants_tenant_idx on public.tenant_occupants(tenant_id) where deleted_at is null;

create table public.emergency_contacts (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  dormitory_id uuid not null references public.dormitories(id) on delete restrict, tenant_id uuid not null references public.tenants(id) on delete restrict,
  name text not null, relationship text not null, phone text not null, is_primary boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz
);
create index emergency_contacts_tenant_idx on public.emergency_contacts(tenant_id) where deleted_at is null;

create table public.tenant_documents (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  dormitory_id uuid not null references public.dormitories(id) on delete restrict, tenant_id uuid not null references public.tenants(id) on delete restrict,
  document_type text not null, storage_path text not null, original_filename text not null, mime_type text not null, size_bytes bigint not null check(size_bytes > 0),
  created_by uuid references public.profiles(id) on delete restrict, created_at timestamptz not null default now(), deleted_at timestamptz
);
create index tenant_documents_tenant_idx on public.tenant_documents(tenant_id) where deleted_at is null;

alter table public.tenant_occupants enable row level security;
alter table public.emergency_contacts enable row level security;
alter table public.tenant_documents enable row level security;

drop policy if exists tenant_staff_scope on public.tenants;
create policy tenant_member_read on public.tenants for select using(public.is_member_of(organization_id));
create policy tenant_member_create on public.tenants for insert with check(public.has_org_permission(organization_id,'tenants.create'));
create policy tenant_member_update on public.tenants for update using(public.has_org_permission(organization_id,'tenants.update')) with check(public.has_org_permission(organization_id,'tenants.update'));

create policy occupant_member_read on public.tenant_occupants for select using(public.is_member_of(organization_id) or public.is_tenant_of(tenant_id));
create policy occupant_member_create on public.tenant_occupants for insert with check(public.has_org_permission(organization_id,'tenants.create'));
create policy occupant_member_update on public.tenant_occupants for update using(public.has_org_permission(organization_id,'tenants.update')) with check(public.has_org_permission(organization_id,'tenants.update'));
create policy emergency_member_read on public.emergency_contacts for select using(public.is_member_of(organization_id) or public.is_tenant_of(tenant_id));
create policy emergency_member_create on public.emergency_contacts for insert with check(public.has_org_permission(organization_id,'tenants.create'));
create policy emergency_member_update on public.emergency_contacts for update using(public.has_org_permission(organization_id,'tenants.update')) with check(public.has_org_permission(organization_id,'tenants.update'));
create policy tenant_document_member_read on public.tenant_documents for select using(public.is_member_of(organization_id) or public.is_tenant_of(tenant_id));
create policy tenant_document_member_create on public.tenant_documents for insert with check(public.has_org_permission(organization_id,'tenants.update'));

grant select, insert, update on public.tenant_occupants, public.emergency_contacts, public.tenant_documents to authenticated;

create or replace function public.create_tenant_with_emergency_contact(
  target_dormitory_id uuid, tenant_title text, tenant_first_name text, tenant_last_name text,
  tenant_nickname text, tenant_phone text, tenant_email text, tenant_id_type text,
  tenant_identity_encrypted text, tenant_identity_last4 text, tenant_birth_date date,
  tenant_registered_address text, tenant_current_address text, tenant_occupation text,
  tenant_workplace text, tenant_vehicle_registration text, tenant_notes text,
  emergency_name text, emergency_relationship text, emergency_phone text
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_org_id uuid; new_tenant_id uuid; sequence_value bigint; sequence_period text; generated_code text;
begin
  select organization_id into target_org_id from public.dormitories where id=target_dormitory_id and deleted_at is null;
  if target_org_id is null then raise exception 'DORMITORY_NOT_FOUND'; end if;
  if not public.has_org_permission(target_org_id,'tenants.create') then raise exception 'FORBIDDEN'; end if;
  if length(trim(tenant_first_name)) < 1 or length(trim(tenant_last_name)) < 1 or length(trim(tenant_phone)) < 9 then raise exception 'INVALID_INPUT'; end if;
  if tenant_id_type not in ('national_id','passport') then raise exception 'INVALID_ID_TYPE'; end if;

  sequence_period := to_char(timezone('Asia/Bangkok', now()), 'YYYY');
  insert into public.document_sequences(organization_id,dormitory_id,document_type,period,current_value,prefix)
  values(target_org_id,target_dormitory_id,'tenant',sequence_period,1,'TEN')
  on conflict(organization_id,dormitory_id,document_type,period)
  do update set current_value=public.document_sequences.current_value+1, updated_at=now()
  returning current_value into sequence_value;
  generated_code := 'TEN-' || sequence_period || '-' || lpad(sequence_value::text,4,'0');

  insert into public.tenants(organization_id,dormitory_id,tenant_code,title,first_name,last_name,nickname,phone,email,id_type,
    national_id_encrypted,national_id_last4,birth_date,registered_address,current_address,occupation,workplace,vehicle_registration,notes)
  values(target_org_id,target_dormitory_id,generated_code,nullif(trim(tenant_title),''),trim(tenant_first_name),trim(tenant_last_name),nullif(trim(tenant_nickname),''),trim(tenant_phone),nullif(lower(trim(tenant_email)),''),tenant_id_type,
    nullif(tenant_identity_encrypted,''),nullif(tenant_identity_last4,''),tenant_birth_date,nullif(trim(tenant_registered_address),''),nullif(trim(tenant_current_address),''),nullif(trim(tenant_occupation),''),nullif(trim(tenant_workplace),''),nullif(trim(tenant_vehicle_registration),''),nullif(trim(tenant_notes),''))
  returning id into new_tenant_id;

  if length(trim(emergency_name)) > 0 then
    insert into public.emergency_contacts(organization_id,dormitory_id,tenant_id,name,relationship,phone)
    values(target_org_id,target_dormitory_id,new_tenant_id,trim(emergency_name),trim(emergency_relationship),trim(emergency_phone));
  end if;
  insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data)
  values(target_org_id,target_dormitory_id,auth.uid(),'tenant.create','tenant',new_tenant_id,
    jsonb_build_object('tenant_code',generated_code,'name',trim(tenant_first_name)||' '||trim(tenant_last_name),'identity_masked',case when tenant_identity_last4 <> '' then '*********'||tenant_identity_last4 else null end));
  return new_tenant_id;
end;
$$;
revoke all on function public.create_tenant_with_emergency_contact(uuid,text,text,text,text,text,text,text,text,text,date,text,text,text,text,text,text,text,text,text) from public,anon;
grant execute on function public.create_tenant_with_emergency_contact(uuid,text,text,text,text,text,text,text,text,text,date,text,text,text,text,text,text,text,text,text) to authenticated;

commit;
