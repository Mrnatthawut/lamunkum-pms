begin;

create table public.contract_templates (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  dormitory_id uuid not null references public.dormitories(id) on delete restrict, code text not null, name text not null,
  active boolean not null default true, current_version_id uuid, created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), version integer not null default 1,
  unique(dormitory_id,code)
);
create table public.contract_versions (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  dormitory_id uuid not null references public.dormitories(id) on delete restrict,
  template_id uuid not null references public.contract_templates(id) on delete restrict, version_number integer not null check(version_number>0),
  body text not null check(length(body) between 100 and 30000), checksum text not null, variables jsonb not null default '[]'::jsonb,
  created_by uuid references public.profiles(id) on delete restrict, created_at timestamptz not null default now(),
  unique(template_id,version_number), unique(template_id,checksum)
);
alter table public.contract_templates add constraint contract_templates_current_version_fk
  foreign key(current_version_id) references public.contract_versions(id) on delete restrict;

create table public.generated_documents (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  dormitory_id uuid not null references public.dormitories(id) on delete restrict,
  document_type text not null check(document_type in ('contract','invoice','receipt','deposit_receipt','deposit_refund','move_out','damage','meter_report')),
  entity_type text not null, entity_id uuid not null, contract_version_id uuid references public.contract_versions(id) on delete restrict,
  template_snapshot text not null, data_snapshot jsonb not null, checksum text not null,
  generated_by uuid references public.profiles(id) on delete restrict, generated_at timestamptz not null default now(),
  voided_at timestamptz, void_reason text,
  unique(document_type,entity_type,entity_id)
);
create index generated_documents_entity_idx on public.generated_documents(organization_id,entity_type,entity_id);

alter table public.contract_templates enable row level security;
alter table public.contract_versions enable row level security;
alter table public.generated_documents enable row level security;
create policy contract_template_member_read on public.contract_templates for select using(public.has_org_permission(organization_id,'contracts.manage'));
create policy contract_template_member_create on public.contract_templates for insert with check(public.has_org_permission(organization_id,'contracts.manage'));
create policy contract_template_member_update on public.contract_templates for update using(public.has_org_permission(organization_id,'contracts.manage')) with check(public.has_org_permission(organization_id,'contracts.manage'));
create policy contract_version_member_read on public.contract_versions for select using(public.has_org_permission(organization_id,'contracts.manage'));
create policy contract_version_member_create on public.contract_versions for insert with check(public.has_org_permission(organization_id,'contracts.manage'));
create policy generated_document_member_read on public.generated_documents for select using(public.has_org_permission(organization_id,'contracts.manage') or (entity_type='contract' and exists(select 1 from public.contracts c where c.id=entity_id and public.is_tenant_of(c.tenant_id))));
create policy generated_document_member_create on public.generated_documents for insert with check(public.has_org_permission(organization_id,'contracts.manage'));
grant select,insert,update on public.contract_templates,public.contract_versions to authenticated;
grant select,insert on public.generated_documents to authenticated;

create or replace function public.create_contract_template_version(target_dormitory_id uuid,target_name text,target_body text)
returns uuid language plpgsql security definer set search_path='' as $$
declare target_org_id uuid; template_record public.contract_templates%rowtype; next_version integer; new_version_id uuid;
  allowed_variables jsonb := '["organization_name","dormitory_name","dormitory_address","contract_number","contract_date","tenant_name","tenant_phone","tenant_address","room_number","start_date","end_date","monthly_rent","deposit","advance_rent","due_day","notice_days","initial_water","initial_electric","inspection_notes","contract_notes"]'::jsonb;
begin
  select organization_id into target_org_id from public.dormitories where id=target_dormitory_id and deleted_at is null;
  if target_org_id is null then raise exception 'DORMITORY_NOT_FOUND'; end if;
  if not public.has_org_permission(target_org_id,'contracts.manage') then raise exception 'FORBIDDEN'; end if;
  if length(trim(target_name))<3 or length(target_body)<100 or length(target_body)>30000 then raise exception 'INVALID_TEMPLATE'; end if;
  select * into template_record from public.contract_templates where dormitory_id=target_dormitory_id and code='lease_contract' for update;
  if template_record.id is null then
    insert into public.contract_templates(organization_id,dormitory_id,code,name,created_by)
    values(target_org_id,target_dormitory_id,'lease_contract',trim(target_name),auth.uid()) returning * into template_record;
  end if;
  select coalesce(max(version_number),0)+1 into next_version from public.contract_versions where template_id=template_record.id;
  insert into public.contract_versions(organization_id,dormitory_id,template_id,version_number,body,checksum,variables,created_by)
  values(target_org_id,target_dormitory_id,template_record.id,next_version,target_body,encode(extensions.digest(convert_to(target_body,'UTF8'),'sha256'),'hex'),allowed_variables,auth.uid())
  returning id into new_version_id;
  update public.contract_templates set name=trim(target_name),current_version_id=new_version_id,updated_at=now(),version=version+1 where id=template_record.id;
  insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data)
  values(target_org_id,target_dormitory_id,auth.uid(),'contract_template.version_create','contract_template',template_record.id,jsonb_build_object('version',next_version,'version_id',new_version_id));
  return new_version_id;
end; $$;

create or replace function public.create_contract_document_snapshot(target_contract_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare c public.contracts%rowtype; version_record public.contract_versions%rowtype; existing_id uuid; new_id uuid; snapshot jsonb;
  tenant_record public.tenants%rowtype; room_record public.rooms%rowtype; dormitory_record public.dormitories%rowtype; organization_record public.organizations%rowtype; move_in_record public.move_ins%rowtype;
begin
  select * into c from public.contracts where id=target_contract_id;
  if c.id is null then raise exception 'CONTRACT_NOT_FOUND'; end if;
  if not public.has_org_permission(c.organization_id,'contracts.manage') then raise exception 'FORBIDDEN'; end if;
  select id into existing_id from public.generated_documents where document_type='contract' and entity_type='contract' and entity_id=c.id;
  if existing_id is not null then return existing_id; end if;
  select cv.* into version_record from public.contract_templates ct join public.contract_versions cv on cv.id=ct.current_version_id
  where ct.dormitory_id=c.dormitory_id and ct.code='lease_contract' and ct.active;
  if version_record.id is null then raise exception 'TEMPLATE_NOT_FOUND'; end if;
  select * into tenant_record from public.tenants where id=c.tenant_id;
  select * into room_record from public.rooms where id=c.room_id;
  select * into dormitory_record from public.dormitories where id=c.dormitory_id;
  select * into organization_record from public.organizations where id=c.organization_id;
  select * into move_in_record from public.move_ins where contract_id=c.id;
  snapshot := jsonb_build_object(
    'organization_name',organization_record.name,'dormitory_name',dormitory_record.name,'dormitory_address',dormitory_record.address,
    'contract_number',c.contract_number,'contract_date',c.contract_date,'tenant_name',concat_ws(' ',nullif(tenant_record.title,''),tenant_record.first_name,tenant_record.last_name),
    'tenant_phone',tenant_record.phone,'tenant_address',coalesce(tenant_record.current_address,tenant_record.registered_address,''),'room_number',room_record.room_number,
    'start_date',c.start_date,'end_date',c.end_date,'monthly_rent',c.monthly_rent,'deposit',c.deposit,'advance_rent',c.advance_rent,
    'due_day',c.due_day,'notice_days',c.notice_days,'initial_water',move_in_record.initial_water_reading,'initial_electric',move_in_record.initial_electric_reading,
    'inspection_notes',coalesce(move_in_record.inspection_notes,''),'contract_notes',coalesce(c.notes,''));
  insert into public.generated_documents(organization_id,dormitory_id,document_type,entity_type,entity_id,contract_version_id,template_snapshot,data_snapshot,checksum,generated_by)
  values(c.organization_id,c.dormitory_id,'contract','contract',c.id,version_record.id,version_record.body,snapshot,
    encode(extensions.digest(convert_to(version_record.body||snapshot::text,'UTF8'),'sha256'),'hex'),auth.uid()) returning id into new_id;
  insert into public.audit_logs(organization_id,dormitory_id,actor_id,action,entity_type,entity_id,after_data)
  values(c.organization_id,c.dormitory_id,auth.uid(),'contract_document.generate','generated_document',new_id,jsonb_build_object('contract_id',c.id,'version_id',version_record.id));
  return new_id;
end; $$;

revoke all on function public.create_contract_template_version(uuid,text,text) from public,anon;
grant execute on function public.create_contract_template_version(uuid,text,text) to authenticated;
revoke all on function public.create_contract_document_snapshot(uuid) from public,anon;
grant execute on function public.create_contract_document_snapshot(uuid) to authenticated;

do $$
declare d record; template_body text := 'สัญญาเช่าห้องพัก\nเลขที่ {{contract_number}}\n\nสัญญานี้ทำขึ้นวันที่ {{contract_date}} ณ {{dormitory_name}} ที่อยู่ {{dormitory_address}}\nระหว่าง {{organization_name}} ซึ่งต่อไปเรียกว่า “ผู้ให้เช่า” กับ {{tenant_name}} โทรศัพท์ {{tenant_phone}} ที่อยู่ {{tenant_address}} ซึ่งต่อไปเรียกว่า “ผู้เช่า”\n\nข้อ 1 ผู้ให้เช่าตกลงให้เช่าห้องหมายเลข {{room_number}} ตั้งแต่วันที่ {{start_date}} ถึงวันที่ {{end_date}}\nข้อ 2 ค่าเช่าเดือนละ {{monthly_rent}} บาท ชำระภายในวันที่ {{due_day}} ของเดือน ค่าเช่าล่วงหน้า {{advance_rent}} บาท\nข้อ 3 เงินประกันตามสัญญา {{deposit}} บาท การรับเงินจริงต้องอ้างอิงใบรับเงินหรือรายการชำระที่ยืนยันแล้ว\nข้อ 4 ผู้เช่าต้องแจ้งย้ายออกล่วงหน้าไม่น้อยกว่า {{notice_days}} วัน และชำระยอดค้างก่อนคืนห้อง\nข้อ 5 มิเตอร์น้ำเริ่มต้น {{initial_water}} หน่วย มิเตอร์ไฟเริ่มต้น {{initial_electric}} หน่วย\nสภาพห้องเมื่อเข้าอยู่: {{inspection_notes}}\nเงื่อนไขเพิ่มเติม: {{contract_notes}}\n\nคู่สัญญาได้อ่านและเข้าใจข้อความโดยตลอดแล้ว จึงลงลายมือชื่อไว้เป็นหลักฐาน\n\nลงชื่อ ____________________ ผู้ให้เช่า        ลงชื่อ ____________________ ผู้เช่า\n\nหมายเหตุ: ควรให้ผู้เชี่ยวชาญกฎหมายไทยตรวจสอบข้อความและวิธีลงนามก่อนนำไปใช้เป็นหลักฐานจริง';
  template_uuid uuid; version_uuid uuid;
begin
  for d in select id,organization_id from public.dormitories where deleted_at is null loop
    insert into public.contract_templates(organization_id,dormitory_id,code,name)
    values(d.organization_id,d.id,'lease_contract','สัญญาเช่ามาตรฐาน') on conflict(dormitory_id,code) do update set name=excluded.name
    returning id into template_uuid;
    if not exists(select 1 from public.contract_versions cv where cv.template_id=template_uuid) then
      insert into public.contract_versions(organization_id,dormitory_id,template_id,version_number,body,checksum,variables)
      values(d.organization_id,d.id,template_uuid,1,template_body,encode(extensions.digest(convert_to(template_body,'UTF8'),'sha256'),'hex'),'[]'::jsonb)
      returning id into version_uuid;
      update public.contract_templates set current_version_id=version_uuid where id=template_uuid;
    end if;
  end loop;
end $$;

commit;
