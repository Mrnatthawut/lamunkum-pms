begin;

create table public.contract_signatures (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  dormitory_id uuid not null references public.dormitories(id) on delete restrict,
  generated_document_id uuid not null references public.generated_documents(id) on delete restrict,
  contract_id uuid not null references public.contracts(id) on delete restrict,
  signer_role text not null check(signer_role in ('owner','tenant')), signer_name text not null,
  signature_method text not null check(signature_method in ('draw','upload')), storage_path text not null,
  mime_type text not null check(mime_type in ('image/png','image/jpeg')), size_bytes bigint not null check(size_bytes between 1 and 2097152),
  signature_sha256 text not null check(signature_sha256 ~ '^[a-f0-9]{64}$'), document_checksum text not null,
  signer_profile_id uuid references public.profiles(id) on delete restrict, signed_at timestamptz not null default now(),
  ip inet, user_agent text, consent_version text not null default 'electronic-signature-v1', created_at timestamptz not null default now(),
  unique(generated_document_id,signer_role), unique(storage_path)
);
create index contract_signatures_contract_idx on public.contract_signatures(contract_id,signed_at);

create table public.room_asset_inspections (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  dormitory_id uuid not null references public.dormitories(id) on delete restrict,
  move_in_id uuid not null references public.move_ins(id) on delete restrict, contract_id uuid not null references public.contracts(id) on delete restrict,
  category text not null check(category in ('floor','wall','door','window','bathroom','air_conditioner','bed','wardrobe','desk','electrical','overall')),
  condition text not null check(condition in ('good','damaged','missing','not_applicable')), notes text,
  created_by uuid references public.profiles(id) on delete restrict, created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), version integer not null default 1,
  unique(move_in_id,category)
);
create table public.room_inspection_attachments (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  dormitory_id uuid not null references public.dormitories(id) on delete restrict,
  inspection_id uuid not null references public.room_asset_inspections(id) on delete restrict,
  storage_path text not null unique, mime_type text not null check(mime_type in ('image/png','image/jpeg','image/webp')),
  size_bytes bigint not null check(size_bytes between 1 and 5242880), file_sha256 text not null check(file_sha256 ~ '^[a-f0-9]{64}$'),
  created_by uuid references public.profiles(id) on delete restrict, created_at timestamptz not null default now()
);

alter table public.contract_signatures enable row level security;
alter table public.room_asset_inspections enable row level security;
alter table public.room_inspection_attachments enable row level security;
create policy signature_member_read on public.contract_signatures for select using(public.has_org_permission(organization_id,'contracts.manage') or exists(select 1 from public.contracts c where c.id=contract_id and public.is_tenant_of(c.tenant_id)));
create policy inspection_member_read on public.room_asset_inspections for select using(public.has_org_permission(organization_id,'contracts.manage') or exists(select 1 from public.contracts c where c.id=contract_id and public.is_tenant_of(c.tenant_id)));
create policy inspection_member_write on public.room_asset_inspections for insert with check(public.has_org_permission(organization_id,'contracts.manage'));
create policy inspection_member_update on public.room_asset_inspections for update using(public.has_org_permission(organization_id,'contracts.manage')) with check(public.has_org_permission(organization_id,'contracts.manage'));
create policy inspection_attachment_member_read on public.room_inspection_attachments for select using(public.has_org_permission(organization_id,'contracts.manage'));
create policy inspection_attachment_member_create on public.room_inspection_attachments for insert with check(public.has_org_permission(organization_id,'contracts.manage'));
grant select on public.contract_signatures to authenticated;
grant select,insert,update on public.room_asset_inspections to authenticated;
grant select,insert on public.room_inspection_attachments to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
('contract-signatures','contract-signatures',false,2097152,array['image/png','image/jpeg']),
('room-inspections','room-inspections',false,5242880,array['image/png','image/jpeg','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

create or replace function public.can_manage_storage_org(object_name text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.organization_members m join public.role_permissions rp on rp.role=m.role
    join public.permissions p on p.id=rp.permission_id where m.profile_id=auth.uid() and m.active
    and m.organization_id::text=split_part(object_name,'/',1) and p.code='contracts.manage')
$$;
revoke all on function public.can_manage_storage_org(text) from public,anon;
grant execute on function public.can_manage_storage_org(text) to authenticated;

create policy contract_signature_object_insert on storage.objects for insert to authenticated
  with check(bucket_id='contract-signatures' and public.can_manage_storage_org(name));
create policy contract_signature_object_read on storage.objects for select to authenticated
  using(bucket_id='contract-signatures' and public.can_manage_storage_org(name));
create policy contract_signature_object_delete on storage.objects for delete to authenticated
  using(bucket_id='contract-signatures' and public.can_manage_storage_org(name));
create policy room_inspection_object_insert on storage.objects for insert to authenticated
  with check(bucket_id='room-inspections' and public.can_manage_storage_org(name));
create policy room_inspection_object_read on storage.objects for select to authenticated
  using(bucket_id='room-inspections' and public.can_manage_storage_org(name));
create policy room_inspection_object_delete on storage.objects for delete to authenticated
  using(bucket_id='room-inspections' and public.can_manage_storage_org(name));

create or replace function public.record_contract_signature(
  target_document_id uuid,target_signer_role text,target_signer_name text,target_method text,target_storage_path text,
  target_mime_type text,target_size_bytes bigint,target_signature_sha256 text,target_ip inet,target_user_agent text
) returns uuid language plpgsql security definer set search_path='' as $$
declare document_record public.generated_documents%rowtype; contract_record public.contracts%rowtype; new_id uuid; required_prefix text;
begin
  select * into document_record from public.generated_documents where id=target_document_id and document_type='contract' and voided_at is null;
  if document_record.id is null then raise exception 'DOCUMENT_NOT_FOUND'; end if;
  if not public.has_org_permission(document_record.organization_id,'contracts.manage') then raise exception 'FORBIDDEN'; end if;
  select * into contract_record from public.contracts where id=document_record.entity_id and document_record.entity_type='contract';
  if contract_record.id is null then raise exception 'CONTRACT_NOT_FOUND'; end if;
  if target_signer_role not in ('owner','tenant') or target_method not in ('draw','upload') then raise exception 'INVALID_SIGNATURE'; end if;
  if length(trim(target_signer_name))<2 or target_mime_type not in ('image/png','image/jpeg') or target_size_bytes not between 1 and 2097152 or target_signature_sha256 !~ '^[a-f0-9]{64}$' then raise exception 'INVALID_SIGNATURE'; end if;
  required_prefix := document_record.organization_id::text||'/'||document_record.dormitory_id::text||'/contracts/'||contract_record.id::text||'/';
  if left(target_storage_path,length(required_prefix))<>required_prefix or target_storage_path like '%..%' then raise exception 'INVALID_STORAGE_PATH'; end if;
  insert into public.contract_signatures(organization_id,dormitory_id,generated_document_id,contract_id,signer_role,signer_name,
    signature_method,storage_path,mime_type,size_bytes,signature_sha256,document_checksum,signer_profile_id,ip,user_agent)
  values(document_record.organization_id,document_record.dormitory_id,document_record.id,contract_record.id,target_signer_role,trim(target_signer_name),
    target_method,target_storage_path,target_mime_type,target_size_bytes,target_signature_sha256,document_record.checksum,auth.uid(),target_ip,left(target_user_agent,500))
  returning id into new_id;
  insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data,ip,user_agent)
  values(document_record.organization_id,document_record.dormitory_id,auth.uid(),'contract.signature_create','contract_signature',new_id,
    jsonb_build_object('contract_id',contract_record.id,'document_id',document_record.id,'signer_role',target_signer_role,'document_checksum',document_record.checksum),target_ip,left(target_user_agent,500));
  return new_id;
end $$;

create or replace function public.save_move_in_inspection(target_contract_id uuid,target_items jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare c public.contracts%rowtype; move_in_record public.move_ins%rowtype; item jsonb; item_category text; item_condition text;
begin
  select * into c from public.contracts where id=target_contract_id;
  if c.id is null then raise exception 'CONTRACT_NOT_FOUND'; end if;
  if not public.has_org_permission(c.organization_id,'contracts.manage') then raise exception 'FORBIDDEN'; end if;
  if exists(select 1 from public.contract_signatures where contract_id=c.id) then raise exception 'CONTRACT_ALREADY_SIGNED'; end if;
  select * into move_in_record from public.move_ins where contract_id=c.id;
  if move_in_record.id is null then raise exception 'MOVE_IN_NOT_FOUND'; end if;
  if jsonb_typeof(target_items)<>'array' or jsonb_array_length(target_items)<1 or jsonb_array_length(target_items)>20 then raise exception 'INVALID_INSPECTION'; end if;
  for item in select * from jsonb_array_elements(target_items) loop
    item_category:=item->>'category'; item_condition:=item->>'condition';
    if item_category not in ('floor','wall','door','window','bathroom','air_conditioner','bed','wardrobe','desk','electrical','overall') or item_condition not in ('good','damaged','missing','not_applicable') then raise exception 'INVALID_INSPECTION'; end if;
    insert into public.room_asset_inspections(organization_id,dormitory_id,move_in_id,contract_id,category,condition,notes,created_by)
    values(c.organization_id,c.dormitory_id,move_in_record.id,c.id,item_category,item_condition,nullif(trim(item->>'notes'),''),auth.uid())
    on conflict(move_in_id,category) do update set condition=excluded.condition,notes=excluded.notes,updated_at=now(),version=public.room_asset_inspections.version+1;
  end loop;
  insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data)
  values(c.organization_id,c.dormitory_id,auth.uid(),'move_in.inspection_save','move_in',move_in_record.id,jsonb_build_object('contract_id',c.id,'item_count',jsonb_array_length(target_items)));
  return move_in_record.id;
end $$;

create or replace function public.prevent_signed_contract_terms_update() returns trigger language plpgsql set search_path='' as $$
begin
  if exists(select 1 from public.contract_signatures where contract_id=old.id) and
    (new.tenant_id,new.room_id,new.contract_date,new.start_date,new.end_date,new.monthly_rent,new.deposit,new.advance_rent,new.due_day,new.notice_days,new.notes)
    is distinct from
    (old.tenant_id,old.room_id,old.contract_date,old.start_date,old.end_date,old.monthly_rent,old.deposit,old.advance_rent,old.due_day,old.notice_days,old.notes)
  then raise exception 'SIGNED_CONTRACT_IMMUTABLE'; end if;
  return new;
end $$;
create trigger protect_signed_contract_terms before update on public.contracts for each row execute function public.prevent_signed_contract_terms_update();

revoke all on function public.record_contract_signature(uuid,text,text,text,text,text,bigint,text,inet,text) from public,anon;
grant execute on function public.record_contract_signature(uuid,text,text,text,text,text,bigint,text,inet,text) to authenticated;
revoke all on function public.save_move_in_inspection(uuid,jsonb) from public,anon;
grant execute on function public.save_move_in_inspection(uuid,jsonb) to authenticated;
revoke all on function public.prevent_signed_contract_terms_update() from public,anon,authenticated;

commit;
